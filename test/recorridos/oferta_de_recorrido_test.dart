import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.dialogs.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/route_batch_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/dialogs/route_batch_offer/route_batch_offer_dialog_model.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';
import 'support.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockRouteBatchRepository repo;

  setUp(() {
    registerServices();
    repo = locator<RouteBatchRepository>() as MockRouteBatchRepository;
  });
  tearDown(() => locator.reset());

  group('modelo de la oferta del recorrido', () {
    RouteBatchOfferDialogModel build(
      RouteBatch b, {
      Stream<RouteBatchEvent>? events,
    }) =>
        RouteBatchOfferDialogModel(
            batch: b,
            repo: repo,
            events: events ?? const Stream<RouteBatchEvent>.empty());

    test('cuenta hasta offer.expiresAt y vence una sola vez', () async {
      final m = build(batch(ttl: const Duration(seconds: 2)));
      final outcomes = <BatchOutcome>[];
      m.start(outcomes.add);
      expect(m.totalSeconds, inInclusiveRange(1, 2));
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(outcomes, [BatchOutcome.expired]);
      expect(m.isFinished, true);
      verifyNever(repo.accept(any));
      m.dispose();
    });

    test('aceptar frena la cuenta y manda el POST antes que nada', () async {
      final accept = Completer<RouteBatchDecision>();
      when(repo.accept('b1')).thenAnswer((_) => accept.future);
      final m = build(batch(ttl: const Duration(seconds: 1)));
      final outcomes = <BatchOutcome>[];
      m.start(outcomes.add);
      final f = m.accept();
      expect(m.isAccepting, true);
      // Un segundo toque no repite el POST.
      await m.accept();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      expect(outcomes, isEmpty,
          reason: 'la cuenta no vence con el POST en vuelo');
      accept.complete(const RouteBatchDecision(
          batchId: 'b1', accepted: true, assignedOrders: 2));
      await f;
      expect(outcomes, [BatchOutcome.accepted]);
      verify(repo.accept('b1')).called(1);
      m.dispose();
    });

    test('un 409 del back termina como rechazado con el texto del back',
        () async {
      when(repo.accept('b1'))
          .thenThrow(http(409, {'message': 'La oferta del lote venció'}));
      final m = build(batch());
      final outcomes = <BatchOutcome>[];
      m.start(outcomes.add);
      await m.accept();
      expect(outcomes, [BatchOutcome.refused]);
      expect(m.acceptError, 'La oferta del lote venció');
      m.dispose();
    });

    test('sin respuesta (red) la cuenta sigue y se puede reintentar', () async {
      var n = 0;
      when(repo.accept('b1')).thenAnswer((_) async {
        if (n++ == 0) throw http(null);
        return const RouteBatchDecision(
            batchId: 'b1', accepted: true, assignedOrders: 2);
      });
      final m = build(batch(ttl: const Duration(seconds: 30)));
      final outcomes = <BatchOutcome>[];
      m.start(outcomes.add);
      await m.accept();
      expect(outcomes, isEmpty);
      expect(m.acceptError, isNotNull);
      expect(m.isAccepting, false);
      expect(m.isFinished, false);
      await m.accept();
      expect(outcomes, [BatchOutcome.accepted]);
      m.dispose();
    });

    test('rechazar frena la cuenta; no manda nada (lo hace quien lo abrió)',
        () async {
      final m = build(batch());
      final outcomes = <BatchOutcome>[];
      m.start(outcomes.add);
      m.reject();
      m.reject();
      expect(outcomes, [BatchOutcome.rejected]);
      verifyNever(repo.reject(any));
      m.dispose();
    });

    test('offer-closed del mismo lote cierra la pantalla; el de otro no',
        () async {
      final c = StreamController<RouteBatchEvent>.broadcast();
      final m = build(batch(), events: c.stream);
      final outcomes = <BatchOutcome>[];
      m.start(outcomes.add);
      c.add(const RouteBatchClosed('otro', 'dissolved'));
      await settle();
      expect(outcomes, isEmpty);
      c.add(const RouteBatchClosed('b1', 'dissolved'));
      await settle();
      expect(outcomes, [BatchOutcome.closed]);
      await c.close();
      m.dispose();
    });

    test('con el POST en vuelo el aviso de cierre no pisa su respuesta',
        () async {
      final c = StreamController<RouteBatchEvent>.broadcast();
      final accept = Completer<RouteBatchDecision>();
      when(repo.accept('b1')).thenAnswer((_) => accept.future);
      final m = build(batch(), events: c.stream);
      final outcomes = <BatchOutcome>[];
      m.start(outcomes.add);
      final f = m.accept();
      c.add(const RouteBatchClosed('b1', 'withdrawn'));
      await settle();
      expect(outcomes, isEmpty);
      accept.complete(const RouteBatchDecision(
          batchId: 'b1', accepted: true, assignedOrders: 2));
      await f;
      expect(outcomes, [BatchOutcome.accepted]);
      await c.close();
      m.dispose();
    });
  });

  group('Inicio: recorridos', () {
    late MockTripService trips;
    late MockNavigationService nav;
    late MockDialogService dialogs;
    late MockDriverSocketService socket;
    late MockDriverAuthService auth;
    late StreamController<RouteBatchEvent> batchEvents;
    late StreamController<Map<String, dynamic>> orders;

    setUp(() {
      trips = locator<TripService>() as MockTripService;
      nav = locator<NavigationService>() as MockNavigationService;
      dialogs = locator<DialogService>() as MockDialogService;
      socket = locator<DriverSocketService>() as MockDriverSocketService;
      auth = locator<DriverAuthService>() as MockDriverAuthService;
      when(auth.token).thenAnswer((_) async => 'tok');
      when(auth.userId).thenReturn('u1');
      when(socket.isConnected).thenReturn(false);
      when(socket.hasSocket).thenReturn(false);
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
      when(trips.activeOrderId).thenReturn(null);
      batchEvents = StreamController<RouteBatchEvent>.broadcast();
      orders = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.routeBatchEvents).thenAnswer((_) => batchEvents.stream);
      when(socket.incomingOrders).thenAnswer((_) => orders.stream);
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'accepted'));
      when(trips.order('o2')).thenAnswer((_) async => trip(status: 'accepted'));
      when(repo.batch('b1')).thenAnswer((_) async => batch());
    });
    tearDown(() async {
      await batchEvents.close();
      await orders.close();
    });

    void dialogAnswers(DialogResponse response) {
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async => response);
    }

    Future<HomeViewModel> online() async {
      final api = MockApiClient();
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      final m = HomeViewModel(trips: trips, apiClient: api);
      await m.connect();
      return m;
    }

    final offered = RouteBatchOffered('b1', expiresAt: DateTime.now());

    test('la oferta abre la pantalla con el lote leído del back', () async {
      dialogAnswers(DialogResponse(
          confirmed: false, data: {'outcome': BatchOutcome.expired}));
      await online();
      batchEvents.add(offered);
      await settle();
      final shown = verify(dialogs.showCustomDialog(
              variant: DialogType.routeBatchOffer,
              data: captureAnyNamed('data'),
              barrierDismissible: false))
          .captured
          .single as RouteBatch;
      expect(shown.stops.map((s) => s.orderId), ['o1', 'o2']);
      // Vencida: el back ya cerró la oferta, no se rechaza.
      verifyNever(repo.reject(any));
    });

    test('aceptar abre las paradas en el orden del recorrido, una por una',
        () async {
      dialogAnswers(DialogResponse(
          confirmed: true, data: {'outcome': BatchOutcome.accepted}));
      final m = await online();
      batchEvents.add(offered);
      await settle();
      verifyInOrder([
        nav.navigateToDeliveryView(orderId: 'o1'),
        nav.navigateToDeliveryView(orderId: 'o2'),
      ]);
      expect(m.batchQueue, isEmpty);
      // El POST de aceptar lo manda la pantalla, no el Inicio.
      verifyNever(repo.accept(any));
      verifyNever(repo.reject(any));
    });

    test('una parada que ya no es del chofer se saltea', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'cancelled'));
      dialogAnswers(DialogResponse(
          confirmed: true, data: {'outcome': BatchOutcome.accepted}));
      await online();
      batchEvents.add(offered);
      await settle();
      verifyNever(nav.navigateToDeliveryView(orderId: 'o1'));
      verify(nav.navigateToDeliveryView(orderId: 'o2')).called(1);
    });

    test('los pedidos del recorrido que llegan como oferta no abren diálogo',
        () async {
      final accepting = Completer<DialogResponse>();
      when(dialogs.showCustomDialog(
              variant: DialogType.routeBatchOffer,
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) => accepting.future);
      await online();
      batchEvents.add(offered);
      await settle();
      // Al aceptar, el back avisa cada pedido por el evento de las ofertas.
      orders.add({'orderId': 'o1', 'event': 'NEW_ORDER'});
      orders.add({'orderId': 'o2', 'event': 'NEW_ORDER'});
      await settle();
      verifyNever(dialogs.showCustomDialog(
          variant: DialogType.orderOffer,
          data: anyNamed('data'),
          barrierDismissible: anyNamed('barrierDismissible')));
      verifyNever(trips.reject(any));
      accepting.complete(DialogResponse(
          confirmed: true, data: {'outcome': BatchOutcome.accepted}));
      await settle();
    });

    test('rechazar manda el POST reject y no abre paradas', () async {
      dialogAnswers(DialogResponse(
          confirmed: false, data: {'outcome': BatchOutcome.rejected}));
      await online();
      batchEvents.add(offered);
      await settle();
      verify(repo.reject('b1')).called(1);
      verifyNever(nav.navigateToDeliveryView(orderId: 'o1'));
      verifyNever(nav.navigateToDeliveryView(orderId: 'o2'));
    });

    test('rechazado por el back: lo dice y no insiste', () async {
      dialogAnswers(DialogResponse(confirmed: false, data: {
        'outcome': BatchOutcome.refused,
        'error': 'Los pedidos del lote ya no están disponibles'
      }));
      await online();
      batchEvents.add(offered);
      await settle();
      verify(dialogs.showDialog(
              title: 'No pudimos aceptar el recorrido',
              description: 'Los pedidos del lote ya no están disponibles'))
          .called(1);
      verifyNever(repo.reject(any));
      verifyNever(nav.navigateToDeliveryView(orderId: 'o1'));
      verifyNever(nav.navigateToDeliveryView(orderId: 'o2'));
    });

    test('offer-closed (cerrado por el despacho) no rechaza nada', () async {
      dialogAnswers(DialogResponse(
          confirmed: false, data: {'outcome': BatchOutcome.closed}));
      await online();
      batchEvents.add(offered);
      await settle();
      verifyNever(repo.reject(any));
    });

    test('con un pedido en curso el recorrido se rechaza sin abrir pantalla',
        () async {
      when(trips.activeOrderId).thenReturn('x');
      await online();
      batchEvents.add(offered);
      await settle();
      verify(repo.reject('b1')).called(1);
      verifyNever(repo.batch(any));
      verifyNever(dialogs.showCustomDialog(
          variant: anyNamed('variant'),
          data: anyNamed('data'),
          barrierDismissible: anyNamed('barrierDismissible')));
    });

    test('si no se puede leer el lote no se abre nada ni se rechaza', () async {
      when(repo.batch('b1')).thenThrow(http(404));
      await online();
      batchEvents.add(offered);
      await settle();
      verifyNever(dialogs.showCustomDialog(
          variant: anyNamed('variant'),
          data: anyNamed('data'),
          barrierDismissible: anyNamed('barrierDismissible')));
      verifyNever(repo.reject(any));
    });

    test('al ponerse en línea muestra el recorrido que quedó esperando',
        () async {
      when(repo.mine()).thenAnswer((_) async => [batch()]);
      dialogAnswers(DialogResponse(
          confirmed: false, data: {'outcome': BatchOutcome.expired}));
      await online();
      await settle();
      verify(dialogs.showCustomDialog(
              variant: DialogType.routeBatchOffer,
              data: anyNamed('data'),
              barrierDismissible: false))
          .called(1);
    });

    test('sin recorridos (módulo apagado) el Inicio no muestra nada', () async {
      when(repo.mine()).thenAnswer((_) async => []);
      await online();
      await settle();
      verifyNever(dialogs.showCustomDialog(
          variant: anyNamed('variant'),
          data: anyNamed('data'),
          barrierDismissible: anyNamed('barrierDismissible')));
    });

    test('un lote vencido o ya asignado en la lista no se muestra', () async {
      when(repo.mine()).thenAnswer((_) async => [
            RouteBatch.fromJson(batchJson(status: 'assigned')),
            RouteBatch.fromJson(batchJson(offerStatus: 'expired')),
            batch(ttl: const Duration(seconds: -5)),
          ]);
      await online();
      await settle();
      verifyNever(dialogs.showCustomDialog(
          variant: anyNamed('variant'),
          data: anyNamed('data'),
          barrierDismissible: anyNamed('barrierDismissible')));
    });
  });
}
