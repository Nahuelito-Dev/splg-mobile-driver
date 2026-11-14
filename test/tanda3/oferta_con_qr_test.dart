import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/delivery_offer_slot.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/delivery_qr/delivery_qr_view.dart';
import 'package:splg_driver/ui/views/delivery_qr/delivery_qr_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery_qr/offer_band_model.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_driver/ui/views/payment/payment_view.dart';
import 'package:splg_driver/ui/views/payment/payment_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

/// Oferta que llega con el QR de entrega arriba (el chofer está «por
/// terminar»): se muestra en una banda abajo, sin tapar el QR ni el código.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> oferta({String id = 'oB', int segundos = 25}) => {
        'orderId': id,
        'totalAmount': 28310,
        'paymentMethod': 'cash',
        'expiresAt':
            DateTime.now().add(Duration(seconds: segundos)).toIso8601String(),
      };

  Future<DialogResponse<dynamic>?> sinPantallaCompleta() =>
      throw StateError('no debería abrirse a pantalla completa');

  group('DeliveryOfferSlot', () {
    test('sin el QR arriba, la oferta va a pantalla completa', () async {
      final slot = DeliveryOfferSlot();
      final r = await slot.show(
          oferta(), () async => DialogResponse(confirmed: true));
      expect(r!.confirmed, true);
      expect(slot.offer, isNull);
    });

    test('con el QR arriba queda en la banda hasta que el chofer contesta',
        () async {
      final slot = DeliveryOfferSlot()..host();
      final o = oferta();
      final f = slot.show(o, sinPantallaCompleta);
      expect(slot.offer!['orderId'], 'oB');
      expect(slot.state, OfferSlotState.pending);
      expect(slot.beginResponse(o), true);
      slot.respond(o, DialogResponse(confirmed: false));
      expect((await f)!.confirmed, false);
      expect(slot.offer, isNull);
      expect(slot.state, OfferSlotState.empty);
    });

    test('una sola respuesta por oferta: la segunda decisión no entra',
        () async {
      final slot = DeliveryOfferSlot()..host();
      final o = oferta();
      final f = slot.show(o, sinPantallaCompleta);
      expect(slot.beginResponse(o), true);
      expect(slot.beginResponse(o), false);
      slot.respond(o, DialogResponse(confirmed: true));
      slot.respond(o, DialogResponse(confirmed: false));
      expect((await f)!.confirmed, true);
      // Una respuesta de otra oferta (vieja) tampoco entra.
      final o2 = oferta(id: 'oC');
      final f2 = slot.show(o2, sinPantallaCompleta);
      slot.respond(o, DialogResponse(confirmed: false));
      expect(slot.offer, same(o2));
      expect(slot.beginResponse(o), false);
      slot.respond(o2, DialogResponse(confirmed: false));
      expect((await f2)!.confirmed, false);
    });

    test('segunda oferta con una en la banda: se rechaza explícito', () async {
      final slot = DeliveryOfferSlot()..host();
      final o = oferta();
      final f = slot.show(o, sinPantallaCompleta);
      final r2 = await slot.show(oferta(id: 'oC'), sinPantallaCompleta);
      expect(r2!.confirmed, false);
      expect(slot.offer, same(o));
      slot.respond(o, DialogResponse(confirmed: true));
      expect((await f)!.confirmed, true);
    });

    test(
        'la pantalla se cierra con la aceptación en vuelo: no se abre el '
        'diálogo y llega una sola respuesta', () async {
      final slot = DeliveryOfferSlot()..host();
      final o = oferta();
      var full = 0;
      final f = slot.show(o, () async {
        full++;
        return DialogResponse(confirmed: false);
      });
      expect(slot.beginResponse(o), true);
      slot.release();
      expect(full, 0);
      expect(slot.state, OfferSlotState.responding);
      slot.respond(o, DialogResponse(confirmed: true));
      expect((await f)!.confirmed, true);
      expect(full, 0);
    });

    test('el cobro toma la banda antes de que el QR la suelte: no hay diálogo',
        () async {
      final slot = DeliveryOfferSlot()..host(); // QR
      final o = oferta();
      final f = slot.show(o, sinPantallaCompleta);
      slot.host(); // cobro
      slot.release(); // se va el QR
      expect(slot.offer, same(o));
      expect(slot.state, OfferSlotState.pending);
      slot.respond(o, DialogResponse(confirmed: false));
      expect((await f)!.confirmed, false);
    });

    test(
        'el aviso sólo va a la pantalla del QR si está arriba; se va al cerrarla',
        () {
      final slot = DeliveryOfferSlot();
      expect(slot.announce('hola'), false);
      expect(slot.notice, isNull);
      slot.host();
      expect(slot.announce('hola'), true);
      expect(slot.notice, 'hola');
      slot.release();
      expect(slot.notice, isNull);
    });

    test('si el QR se cierra sin decidir, sigue a pantalla completa', () async {
      final slot = DeliveryOfferSlot()..host();
      var full = 0;
      final f = slot.show(oferta(), () async {
        full++;
        return DialogResponse(confirmed: true);
      });
      slot.release();
      expect((await f)!.confirmed, true);
      expect(full, 1);
      expect(slot.hosting, false);
      expect(slot.offer, isNull);
    });
  });

  group('banda: modelo', () {
    late MockTripService trips;
    setUp(() {
      registerServices();
      trips = locator<TripService>() as MockTripService;
      when(trips.order('oB')).thenAnswer((_) async => trip(status: 'pending'));
      when(trips.customerRating('c1')).thenAnswer((_) async => null);
    });
    tearDown(() => locator.reset());

    test('aceptar acepta en el back y contesta como el diálogo, sin mapa',
        () async {
      final slot = DeliveryOfferSlot()..host();
      final f = slot.show(oferta(), sinPantallaCompleta);
      when(trips.setStatus('oB', 'accepted')).thenAnswer((_) async {});
      final m = OfferBandModel(offer: slot.offer!, slot: slot, trips: trips);
      m.begin();
      await m.accept();
      final r = (await f)!;
      expect(r.confirmed, true);
      expect(r.data['map'], 'stay');
      expect(r.data['accepted'], true);
      expect(r.data['refused'], false);
      verify(trips.setStatus('oB', 'accepted')).called(1);
      m.dispose();
    });

    test('el back rechaza la aceptación: contesta refused con su mensaje',
        () async {
      final slot = DeliveryOfferSlot()..host();
      final f = slot.show(oferta(), sinPantallaCompleta);
      when(trips.setStatus('oB', 'accepted')).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          response: Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 409,
              data: {'message': 'El pedido ya fue tomado'})));
      final m = OfferBandModel(offer: slot.offer!, slot: slot, trips: trips);
      await m.accept();
      final r = (await f)!;
      expect(r.data['refused'], true);
      expect(r.data['error'], isNotNull);
      m.dispose();
    });

    test(
        'aceptación en vuelo y la pantalla se cierra (interleaving real): '
        'no se abre el diálogo, una sola respuesta, un solo setStatus',
        () async {
      final slot = DeliveryOfferSlot()..host();
      var full = 0;
      final f = slot.show(oferta(), () async {
        full++;
        return DialogResponse(confirmed: false);
      });
      final back = Completer<void>();
      when(trips.setStatus('oB', 'accepted')).thenAnswer((_) => back.future);
      final m = OfferBandModel(offer: slot.offer!, slot: slot, trips: trips);
      m.begin();
      final aceptando = m.accept();
      await Future<void>.delayed(Duration.zero);
      // Se cierra la pantalla (entrega confirmada o cancelada) en pleno vuelo.
      m.dispose();
      slot.release();
      expect(full, 0);
      // Otra banda (otra pantalla) no puede contestar la misma oferta.
      final otra = OfferBandModel(offer: m.offer, slot: slot, trips: trips);
      otra.reject();
      back.complete();
      await aceptando;
      final r = (await f)!;
      expect(r.confirmed, true);
      expect(r.data['accepted'], true);
      expect(full, 0);
      verify(trips.setStatus('oB', 'accepted')).called(1);
      otra.dispose();
    });

    test('rechazar contesta que no', () async {
      final slot = DeliveryOfferSlot()..host();
      final f = slot.show(oferta(), sinPantallaCompleta);
      final m = OfferBandModel(offer: slot.offer!, slot: slot, trips: trips);
      m.reject();
      expect((await f)!.confirmed, false);
      verifyNever(trips.setStatus(any, any));
      m.dispose();
    });
  });

  group('pantalla del QR con una oferta', () {
    late MockTripService trips;
    late DeliveryOfferSlot slot;

    setUp(() {
      registerServices();
      trips = locator<TripService>() as MockTripService;
      slot = DeliveryOfferSlot();
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      when(trips.order('oB')).thenAnswer((_) async => trip(status: 'pending'));
      when(trips.customerRating('c1')).thenAnswer((_) async => null);
      when(trips.deliveryCode('o1'))
          .thenAnswer((_) async => const DeliveryCodeInfo('482913'));
      DeliveryQrView.debugViewModelFactory = (id) => DeliveryQrViewModel(
          orderId: id,
          trips: trips,
          offers: slot,
          pollInterval: const Duration(hours: 1));
    });
    tearDown(() {
      DeliveryQrView.debugViewModelFactory = null;
      locator.reset();
    });

    Future<void> montar(WidgetTester t) async {
      await loadAppFonts();
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: const DeliveryQrView(orderId: 'o1')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    bool visible(WidgetTester t, Finder f) {
      final r = t.getRect(f);
      return r.top >= 0 && r.bottom <= 852;
    }

    testWidgets('la banda aparece abajo y el QR y el código siguen a la vista',
        (t) async {
      await montar(t);
      expect(slot.hosting, true);
      unawaited(slot.show(oferta(), sinPantallaCompleta));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      final band = find.byKey(const Key('offer-band'));
      expect(band, findsOneWidget);
      expect(find.byKey(const Key('qr-code')), findsOneWidget);
      expect(find.text('482 913'), findsOneWidget);
      expect(visible(t, find.byKey(const Key('qr-code'))), true);
      expect(visible(t, find.byKey(const Key('qr-code-text'))), true);
      // La banda no se superpone con el QR ni con el código.
      final top = t.getRect(band).top;
      expect(t.getRect(find.byKey(const Key('qr-code'))).bottom <= top, true);
      expect(
          t.getRect(find.byKey(const Key('qr-code-text'))).bottom <= top, true);
      expect(find.textContaining('La oferta vence en'), findsOneWidget);
      expect(find.text(r'$28.310'), findsWidgets);
      final o = slot.offer!;
      slot.beginResponse(o);
      slot.respond(o, DialogResponse(confirmed: false));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('«Rechazar» en la banda contesta que no y la banda se va',
        (t) async {
      await montar(t);
      DialogResponse<dynamic>? r;
      slot.show(oferta(), sinPantallaCompleta).then((v) => r = v);
      await t.pump();
      await t.tap(find.byKey(const Key('offer-band-reject')));
      await t.pump();
      expect(r?.confirmed, false);
      expect(find.byKey(const Key('offer-band')), findsNothing);
      expect(find.byKey(const Key('qr-code')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('al vencer la cuenta contesta que no', (t) async {
      await montar(t);
      DialogResponse<dynamic>? r;
      slot.show(oferta(segundos: 2), sinPantallaCompleta).then((v) => r = v);
      await t.pump();
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(r?.confirmed, false);
      expect(find.byKey(const Key('offer-band')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('el aviso de próximo pedido no tapa el QR ni el código',
        (t) async {
      await montar(t);
      slot.announce('Aceptaste un pedido más: te lo mostramos apenas '
          'termines esta entrega.');
      await t.pump();
      final aviso = find.byKey(const Key('offer-notice'));
      expect(aviso, findsOneWidget);
      final top = t.getRect(aviso).top;
      expect(t.getRect(find.byKey(const Key('qr-code'))).bottom <= top, true);
      expect(
          t.getRect(find.byKey(const Key('qr-code-text'))).bottom <= top, true);
      // No es un diálogo: el QR sigue respondiendo.
      expect(find.byType(Dialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(slot.notice, isNull);
    });

    testWidgets('al cerrarse el QR la pantalla deja de hospedar ofertas',
        (t) async {
      await montar(t);
      expect(slot.hosting, true);
      await t.pumpWidget(const SizedBox());
      expect(slot.hosting, false);
    });
  });

  group('pantalla del cobro con una oferta', () {
    late MockTripService trips;
    late DeliveryOfferSlot slot;

    setUp(() {
      registerServices();
      trips = locator<TripService>() as MockTripService;
      slot = DeliveryOfferSlot();
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      when(trips.order('oB')).thenAnswer((_) async => trip(status: 'pending'));
      when(trips.customerRating(any)).thenAnswer((_) async => null);
      PaymentView.debugViewModelFactory =
          (id) => PaymentViewModel(orderId: id, trips: trips, offers: slot);
    });
    tearDown(() {
      PaymentView.debugViewModelFactory = null;
      locator.reset();
    });

    testWidgets(
        'la oferta va en la banda abajo, sin tapar el cobro; al irse el cobro '
        'una oferta sin decidir pasa a pantalla completa', (t) async {
      await loadAppFonts();
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme, home: const PaymentView(orderId: 'o1')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(slot.hosting, true);
      var full = 0;
      unawaited(slot.show(oferta(), () async {
        full++;
        return DialogResponse(confirmed: false);
      }));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      final band = find.byKey(const Key('offer-band'));
      expect(band, findsOneWidget);
      final confirmar = find.byKey(const Key('payment-confirm'));
      expect(confirmar, findsOneWidget);
      expect(t.getRect(confirmar).bottom <= t.getRect(band).top, true);
      expect(find.byType(Dialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(full, 1);
      expect(slot.hosting, false);
    });
  });

  group('Inicio: oferta con el QR arriba', () {
    late MockTripService trips;
    late MockDialogService dialogs;
    late MockDriverSocketService socket;
    late MockDriverApiService driverApi;
    late StreamController<Map<String, dynamic>> offers;
    late StreamController<Map<String, dynamic>> cancelled;
    late DeliveryOfferSlot slot;
    final vms = <HomeViewModel>[];

    setUp(() {
      registerServices();
      slot = locator<DeliveryOfferSlot>();
      trips = locator<TripService>() as MockTripService;
      dialogs = locator<DialogService>() as MockDialogService;
      socket = locator<DriverSocketService>() as MockDriverSocketService;
      final auth = locator<DriverAuthService>() as MockDriverAuthService;
      driverApi = locator<DriverApiService>() as MockDriverApiService;
      offers = StreamController<Map<String, dynamic>>.broadcast();
      cancelled = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.orderCancelled).thenAnswer((_) => cancelled.stream);
      when(driverApi.profile(refresh: anyNamed('refresh'))).thenAnswer(
          (_) async => const DriverProfile(
              userId: 'u1', fullName: 'Chofer', deliveryId: 'd1'));
      when(auth.token).thenAnswer((_) async => 'tok');
      when(auth.userId).thenReturn('u1');
      when(socket.isConnected).thenReturn(false);
      when(socket.hasSocket).thenReturn(false);
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
      when(socket.incomingOrders).thenAnswer((_) => offers.stream);
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async =>
              DialogResponse(confirmed: true, data: {'map': 'stay'}));
      when(trips.activeOrderId).thenReturn('oA');
      when(driverApi.activeOrder()).thenAnswer((_) async => DriverOrder(
          id: 'oA',
          status: DriverOrderStatus.onTheWay,
          total: 1,
          createdAt: DateTime(2026, 11, 2)));
    });

    tearDown(() async {
      for (final m in vms) {
        try {
          m.dispose();
        } catch (_) {}
      }
      vms.clear();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await offers.close();
      await cancelled.close();
      NavigationLauncher.launcher = null;
      locator.reset();
    });

    Future<HomeViewModel> conectado() async {
      final api = MockApiClient();
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      final m = HomeViewModel(trips: trips, apiClient: api);
      vms.add(m);
      await m.connect();
      return m;
    }

    test('no abre el diálogo a pantalla completa: va a la banda', () async {
      slot.host();
      await conectado();
      offers.add({'orderId': 'oB', 'event': 'NEW_ORDER'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verifyNever(dialogs.showCustomDialog(
          variant: anyNamed('variant'),
          data: anyNamed('data'),
          barrierDismissible: anyNamed('barrierDismissible')));
      expect(slot.offer?['orderId'], 'oB');
      // Rechazada en la banda (el modelo real): el back la pasa a otro chofer.
      final band = OfferBandModel(offer: slot.offer!, slot: slot, trips: trips);
      band.reject();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      verify(trips.reject('oB')).called(1);
      band.dispose();
    });

    test('aceptada en la banda queda como próximo pedido', () async {
      slot.host();
      final m = await conectado();
      offers.add({'orderId': 'oB', 'event': 'NEW_ORDER'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // «Aceptar» en la banda (el modelo real, con el back mockeado).
      when(trips.setStatus('oB', 'accepted')).thenAnswer((_) async {});
      final band = OfferBandModel(offer: slot.offer!, slot: slot, trips: trips);
      await band.accept();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(m.queuedOrderId, 'oB');
      verifyNever(trips.reject('oB'));
      // Se aceptó una sola vez (la banda); el Inicio no vuelve a aceptar.
      verify(trips.setStatus('oB', 'accepted')).called(1);
      band.dispose();
      // El «Tu próximo pedido» no tapa el QR: va como aviso en esa pantalla.
      verifyNever(dialogs.showDialog(
          title: 'Tu próximo pedido', description: anyNamed('description')));
      expect(slot.notice, contains('Aceptaste un pedido más'));
    });

    test('asignación manual con el QR arriba: aviso abajo, sin diálogo',
        () async {
      slot.host();
      final m = await conectado();
      offers.add({'orderId': 'oC', 'event': 'NEW_ORDER', 'assigned': true});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(m.queuedOrderId, 'oC');
      verifyNever(dialogs.showDialog(
          title: 'Tu próximo pedido', description: anyNamed('description')));
      expect(slot.notice, contains('Te asignaron un pedido más'));
    });

    test('asignación manual sin el QR arriba: sigue el diálogo', () async {
      final m = await conectado();
      offers.add({'orderId': 'oC', 'event': 'NEW_ORDER', 'assigned': true});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(m.queuedOrderId, 'oC');
      verify(dialogs.showDialog(
              title: 'Tu próximo pedido', description: anyNamed('description')))
          .called(1);
    });

    test('sin el QR arriba, la oferta sigue a pantalla completa', () async {
      await conectado();
      offers.add({'orderId': 'oB', 'event': 'NEW_ORDER'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verify(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .called(1);
    });
  });
}
