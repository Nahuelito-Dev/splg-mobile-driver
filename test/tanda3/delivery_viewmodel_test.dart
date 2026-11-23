import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

void main() {
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDialogService dialogs;
  late MockDriverSocketService socket;
  late MockLocationService loc;
  late int homeCalls;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    dialogs = locator<DialogService>() as MockDialogService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    loc = locator<LocationService>() as MockLocationService;
    when(loc.currentPosition).thenReturn(fix());
    homeCalls = 0;
    when(trips.order('o1')).thenAnswer((_) async => trip());
    when(trips.customerRating('c1')).thenAnswer((_) async => null);
  });
  tearDown(() => locator.reset());

  DeliveryViewModel build() => DeliveryViewModel(
        orderId: 'o1',
        trips: trips,
        pollInterval: const Duration(milliseconds: 20),
        goHome: () => homeCalls++,
      );

  DioException rejected() => DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 400,
          data: {'message': 'El pedido no está en camino'}));

  group('estado inicial', () {
    test('sin cargar nada no hay estado ni coordenadas', () {
      final m = build();
      expect(m.isAccepted, false);
      expect(m.isOnTheWay, false);
      expect(m.destination, isNull);
      expect(m.distanceText, isNull);
      m.dispose();
    });

    test('carga el pedido aceptado con su destino', () async {
      final m = build();
      await m.initialize();
      expect(m.isAccepted, true);
      expect(m.destination!.latitude, closeTo(-27.357482, 1e-6));
      expect(m.markers.map((x) => x.markerId.value), contains('destination'));
      m.dispose();
    });

    test('si falla la carga deja el error y se puede reintentar', () async {
      when(trips.order('o1'))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '')));
      final m = build();
      await m.initialize();
      expect(m.order, isNull);
      expect(m.loadError, 'Sin conexión. Revisá tu internet.');
      when(trips.order('o1')).thenAnswer((_) async => trip());
      await m.retry();
      expect(m.order, isNotNull);
      expect(m.loadError, isNull);
      m.dispose();
    });
  });

  group('transiciones', () {
    test('salir hacia el cliente manda on_the_way y relee el pedido', () async {
      final m = build();
      await m.initialize();
      when(trips.setStatus('o1', 'on_the_way')).thenAnswer((_) async {});
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      await m.markOnTheWay();
      verify(trips.setStatus('o1', 'on_the_way')).called(1);
      expect(m.isOnTheWay, true);
      m.dispose();
    });

    test('salir sólo vale desde "aceptado"', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      final m = build();
      await m.initialize();
      await m.markOnTheWay();
      verifyNever(trips.setStatus(any, any));
      m.dispose();
    });

    test('si el back rechaza salir muestra su mensaje y no cambia de estado',
        () async {
      final m = build();
      await m.initialize();
      when(trips.setStatus('o1', 'on_the_way')).thenThrow(rejected());
      await m.markOnTheWay();
      expect(m.errorMessage, 'El pedido no está en camino');
      expect(m.isAccepted, true);
      expect(m.isUpdatingStatus, false);
      m.dispose();
    });

    test('llegué: avisa al cliente y abre el QR; no avisa dos veces', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      final m = build();
      await m.initialize();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenAnswer((_) async {});
      await m.arriveAndDeliver();
      await m.arriveAndDeliver();
      verify(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .called(1);
      verify(nav.navigateToDeliveryCodeView(orderId: 'o1')).called(2);
      m.dispose();
    });

    test('llegué: si el aviso falla no abre el QR', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      final m = build();
      await m.initialize();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenThrow(rejected());
      await m.arriveAndDeliver();
      expect(m.errorMessage, isNotNull);
      expect(m.arrivedNotified, false);
      verifyNever(nav.navigateToDeliveryCodeView(orderId: 'o1'));
      m.dispose();
    });

    test('llegué sólo vale en camino', () async {
      final m = build();
      await m.initialize();
      await m.arriveAndDeliver();
      verifyNever(trips.arrived(any,
          latitude: anyNamed('latitude'), longitude: anyNamed('longitude')));
      m.dispose();
    });
  });

  group('llegué con control de distancia (v2)', () {
    final now = DateTime(2026, 11, 13, 10);

    DeliveryViewModel buildAt() => DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          pollInterval: const Duration(hours: 1),
          goHome: () => homeCalls++,
          clock: () => now,
        );

    Future<DeliveryViewModel> onTheWay() async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      final m = buildAt();
      await m.initialize();
      return m;
    }

    DioException tooFar() => DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 409,
            data: {
              'statusCode': 409,
              'code': 'ARRIVAL_TOO_FAR',
              'message': 'Todavía estás a 320 m del domicilio. Marcá «Llegué» '
                  'cuando estés en la puerta.',
              'distanceMeters': 320,
              'radiusMeters': 100,
            }));

    test('200: manda la posición actual, avisa y abre la entrega', () async {
      when(loc.currentPosition).thenReturn(fix(
          lat: -27.3576,
          lng: -55.8905,
          at: now.subtract(const Duration(seconds: 5))));
      final m = await onTheWay();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenAnswer((_) async {});
      await m.arriveAndDeliver();
      verify(trips.arrived('o1', latitude: -27.3576, longitude: -55.8905))
          .called(1);
      verifyNever(loc.readFreshPosition(timeout: anyNamed('timeout')));
      expect(m.arrivedNotified, true);
      expect(m.errorMessage, isNull);
      verify(nav.navigateToDeliveryCodeView(orderId: 'o1')).called(1);
      m.dispose();
    });

    test(
        '409 ARRIVAL_TOO_FAR: muestra el mensaje del back, no abre la entrega '
        'y deja reintentar', () async {
      when(loc.currentPosition).thenReturn(fix(at: now));
      final m = await onTheWay();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenThrow(tooFar());
      await m.arriveAndDeliver();
      const text = 'Todavía estás a 320 m del domicilio. Marcá «Llegué» '
          'cuando estés en la puerta.';
      expect(m.errorMessage, text);
      verify(dialogs.showDialog(
              title: 'Todavía no llegaste',
              description: text,
              buttonTitle: 'Entendido'))
          .called(1);
      expect(m.arrivedNotified, false);
      expect(m.isUpdatingStatus, false);
      verifyNever(nav.navigateToDeliveryCodeView(orderId: 'o1'));

      // Ya en la puerta: el reintento pasa y abre la entrega.
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenAnswer((_) async {});
      await m.arriveAndDeliver();
      expect(m.arrivedNotified, true);
      expect(m.errorMessage, isNull);
      verify(nav.navigateToDeliveryCodeView(orderId: 'o1')).called(1);
      m.dispose();
    });

    test('409 ARRIVAL_TOO_FAR sin message: texto de respaldo', () async {
      when(loc.currentPosition).thenReturn(fix(at: now));
      final m = await onTheWay();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                  requestOptions: RequestOptions(path: ''),
                  statusCode: 409,
                  data: {'code': 'ARRIVAL_TOO_FAR'})));
      await m.arriveAndDeliver();
      expect(m.errorMessage, kArrivalTooFarText);
      m.dispose();
    });

    test('otro 409 (estado): se muestra en la hoja, sin el diálogo de lejos',
        () async {
      when(loc.currentPosition).thenReturn(fix(at: now));
      final m = await onTheWay();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                  requestOptions: RequestOptions(path: ''),
                  statusCode: 409,
                  data: {
                    'statusCode': 409,
                    'code': 'ORDER_NOT_ON_THE_WAY',
                    'message':
                        'El pedido debe estar en camino para avisar llegada',
                  })));
      await m.arriveAndDeliver();
      expect(
          m.errorMessage, 'El pedido debe estar en camino para avisar llegada');
      verifyNever(dialogs.showDialog(
          title: 'Todavía no llegaste',
          description: anyNamed('description'),
          buttonTitle: anyNamed('buttonTitle')));
      verifyNever(nav.navigateToDeliveryCodeView(orderId: 'o1'));
      m.dispose();
    });

    test('la lectura no llega a tiempo: no llama al back y lo dice', () async {
      when(loc.currentPosition).thenReturn(null);
      when(loc.readFreshPosition(timeout: anyNamed('timeout'))).thenAnswer(
          (_) async => const PositionRead.blocked(LocationBlock.unreadable));
      final m = await onTheWay();
      await m.arriveAndDeliver();
      expect(
          m.errorMessage,
          'No pudimos leer tu ubicación a tiempo. Esperá unos segundos y probá '
          'de nuevo.');
      verifyNever(trips.arrived(any,
          latitude: anyNamed('latitude'), longitude: anyNamed('longitude')));
      verifyNever(nav.navigateToDeliveryCodeView(orderId: 'o1'));
      expect(m.isUpdatingStatus, false);
      m.dispose();
    });

    test('ubicación vieja (más de 30 s): pide una lectura nueva y manda esa',
        () async {
      when(loc.currentPosition).thenReturn(fix(
          lat: -27.30,
          lng: -55.80,
          at: now.subtract(const Duration(seconds: 31))));
      when(loc.readFreshPosition(timeout: anyNamed('timeout'))).thenAnswer(
          (_) async =>
              PositionRead.ok(fix(lat: -27.3575, lng: -55.8904, at: now)));
      final m = await onTheWay();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenAnswer((_) async {});
      await m.arriveAndDeliver();
      verify(loc.readFreshPosition(timeout: kArrivalPositionTimeout)).called(1);
      verify(trips.arrived('o1', latitude: -27.3575, longitude: -55.8904))
          .called(1);
      verifyNever(trips.arrived('o1', latitude: -27.30, longitude: -55.80));
      m.dispose();
    });

    test('ubicación de 30 s justos todavía sirve: no pide lectura nueva',
        () async {
      when(loc.currentPosition).thenReturn(fix(
          lat: -27.30,
          lng: -55.80,
          at: now.subtract(const Duration(seconds: 30))));
      final m = await onTheWay();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenAnswer((_) async {});
      await m.arriveAndDeliver();
      verifyNever(loc.readFreshPosition(timeout: anyNamed('timeout')));
      verify(trips.arrived('o1', latitude: -27.30, longitude: -55.80))
          .called(1);
      m.dispose();
    });

    group('posición reciente pero sin ubicación disponible', () {
      Future<DeliveryViewModel> blockedWith(LocationBlock block) async {
        when(loc.currentPosition)
            .thenReturn(fix(at: now.subtract(const Duration(seconds: 5))));
        when(loc.locationBlock()).thenAnswer((_) async => block);
        return onTheWay();
      }

      void expectNothingSent() {
        verifyNever(trips.arrived(any,
            latitude: anyNamed('latitude'), longitude: anyNamed('longitude')));
        verifyNever(loc.readFreshPosition(timeout: anyNamed('timeout')));
        verifyNever(nav.navigateToDeliveryCodeView(orderId: 'o1'));
      }

      test('GPS apagado: no manda la posición guardada y pide prenderlo',
          () async {
        final m = await blockedWith(LocationBlock.serviceDisabled);
        await m.arriveAndDeliver();
        expect(
            m.errorMessage, 'Tenés el GPS apagado. Activalo y probá de nuevo.');
        expectNothingSent();
        expect(m.isUpdatingStatus, false);
        m.dispose();
      });

      test('GPS apagado: no pide el permiso', () async {
        final m = await blockedWith(LocationBlock.serviceDisabled);
        await m.arriveAndDeliver();
        verifyNever(loc.requestLocationPermission());
        m.dispose();
      });

      test('permiso revocado y lo da al pedírselo: lee el GPS de nuevo y manda',
          () async {
        when(loc.currentPosition).thenReturn(fix(
            lat: -27.30,
            lng: -55.80,
            at: now.subtract(const Duration(seconds: 5))));
        final blocks = <LocationBlock?>[LocationBlock.permissionDenied, null];
        when(loc.locationBlock()).thenAnswer((_) async => blocks.removeAt(0));
        when(loc.requestLocationPermission()).thenAnswer((_) async => true);
        when(loc.readFreshPosition(timeout: anyNamed('timeout'))).thenAnswer(
            (_) async =>
                PositionRead.ok(fix(lat: -27.3575, lng: -55.8904, at: now)));
        final m = await onTheWay();
        when(trips.arrived('o1',
                latitude: anyNamed('latitude'),
                longitude: anyNamed('longitude')))
            .thenAnswer((_) async {});
        await m.arriveAndDeliver();
        verify(loc.requestLocationPermission()).called(1);
        verify(loc.readFreshPosition(timeout: kArrivalPositionTimeout))
            .called(1);
        verify(trips.arrived('o1', latitude: -27.3575, longitude: -55.8904))
            .called(1);
        expect(m.errorMessage, isNull);
        verify(nav.navigateToDeliveryCodeView(orderId: 'o1')).called(1);
        m.dispose();
      });

      test('permiso revocado y lo niega al pedírselo: no manda y lo dice',
          () async {
        final m = await blockedWith(LocationBlock.permissionDenied);
        when(loc.requestLocationPermission()).thenAnswer((_) async => false);
        await m.arriveAndDeliver();
        verify(loc.requestLocationPermission()).called(1);
        expect(
            m.errorMessage,
            'La app no tiene permiso para usar tu ubicación. Permitilo y '
            'probá de nuevo.');
        expectNothingSent();
        verifyNever(dialogs.showDialog(
            title: 'Ubicación bloqueada',
            description: anyNamed('description'),
            buttonTitle: anyNamed('buttonTitle'),
            cancelTitle: anyNamed('cancelTitle')));
        m.dispose();
      });

      test('permiso bloqueado para siempre: ofrece abrir Ajustes y los abre',
          () async {
        when(dialogs.showDialog(
                title: 'Ubicación bloqueada',
                description: anyNamed('description'),
                buttonTitle: 'Abrir Ajustes',
                cancelTitle: 'Ahora no'))
            .thenAnswer((_) async => DialogResponse(confirmed: true));
        final m = await blockedWith(LocationBlock.permissionPermanentlyDenied);
        await m.arriveAndDeliver();
        verifyNever(loc.requestLocationPermission());
        const text = 'La ubicación está bloqueada para la app. Habilitala en '
            'Ajustes y probá de nuevo.';
        expect(m.errorMessage, text);
        verify(dialogs.showDialog(
                title: 'Ubicación bloqueada',
                description: text,
                buttonTitle: 'Abrir Ajustes',
                cancelTitle: 'Ahora no'))
            .called(1);
        verify(loc.openDeviceSettings()).called(1);
        expectNothingSent();
        m.dispose();
      });

      test('permiso bloqueado y el chofer elige «Ahora no»: no abre Ajustes',
          () async {
        when(dialogs.showDialog(
                title: 'Ubicación bloqueada',
                description: anyNamed('description'),
                buttonTitle: anyNamed('buttonTitle'),
                cancelTitle: anyNamed('cancelTitle')))
            .thenAnswer((_) async => DialogResponse(confirmed: false));
        final m = await blockedWith(LocationBlock.permissionPermanentlyDenied);
        await m.arriveAndDeliver();
        verifyNever(loc.openDeviceSettings());
        expectNothingSent();
        m.dispose();
      });
    });

    test(
        'posición con hora futura no cuenta como fresca: pide una lectura nueva',
        () async {
      when(loc.currentPosition).thenReturn(fix(
          lat: -27.30, lng: -55.80, at: now.add(const Duration(seconds: 5))));
      when(loc.readFreshPosition(timeout: anyNamed('timeout'))).thenAnswer(
          (_) async =>
              PositionRead.ok(fix(lat: -27.3575, lng: -55.8904, at: now)));
      final m = await onTheWay();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenAnswer((_) async {});
      await m.arriveAndDeliver();
      verify(loc.readFreshPosition(timeout: kArrivalPositionTimeout)).called(1);
      verify(trips.arrived('o1', latitude: -27.3575, longitude: -55.8904))
          .called(1);
      m.dispose();
    });

    test('mientras se envía no admite un segundo toque', () async {
      when(loc.currentPosition).thenReturn(fix(at: now));
      final m = await onTheWay();
      final pending = Completer<void>();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenAnswer((_) => pending.future);
      final first = m.arriveAndDeliver();
      expect(m.isUpdatingStatus, true);
      await m.arriveAndDeliver();
      await m.arriveAndDeliver();
      pending.complete();
      await first;
      verify(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .called(1);
      verify(nav.navigateToDeliveryCodeView(orderId: 'o1')).called(1);
      expect(m.isUpdatingStatus, false);
      m.dispose();
    });

    test('mientras se lee la ubicación tampoco admite un segundo toque',
        () async {
      when(loc.currentPosition).thenReturn(null);
      final reading = Completer<PositionRead>();
      when(loc.readFreshPosition(timeout: anyNamed('timeout')))
          .thenAnswer((_) => reading.future);
      final m = await onTheWay();
      when(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .thenAnswer((_) async {});
      final first = m.arriveAndDeliver();
      await m.arriveAndDeliver();
      reading.complete(PositionRead.ok(fix(at: now)));
      await first;
      verify(loc.readFreshPosition(timeout: anyNamed('timeout'))).called(1);
      verify(trips.arrived('o1',
              latitude: anyNamed('latitude'), longitude: anyNamed('longitude')))
          .called(1);
      m.dispose();
    });
  });

  group('cancelaciones y entrega detectadas por polling', () {
    test('el cliente cancela: corta el tracking, avisa y vuelve al Inicio',
        () async {
      final m = build();
      await m.initialize();
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'cancelled'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verify(socket.stopTracking()).called(1);
      verify(dialogs.showDialog(
              title: 'Pedido cancelado', description: anyNamed('description')))
          .called(1);
      expect(homeCalls, 1);
      m.dispose();
    });

    test(
        'cancelado: la tarjeta superior dice "Cancelado", no "Pedido aceptado"',
        () async {
      final m = build();
      await m.initialize();
      expect(m.statusText, 'Pedido aceptado');
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'cancelled'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(m.statusText, 'Cancelado');
      m.dispose();
    });

    test('liberado a pending: también lo avisa', () async {
      final m = build();
      await m.initialize();
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'pending'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verify(dialogs.showDialog(
              title: 'Pedido liberado', description: anyNamed('description')))
          .called(1);
      expect(m.statusText, 'Pedido liberado');
      expect(homeCalls, 1);
      m.dispose();
    });

    test('aviso por socket de otro pedido se ignora; del propio relee',
        () async {
      final c = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.orderCancelled).thenAnswer((_) => c.stream);
      final m = DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          pollInterval: const Duration(hours: 1),
          goHome: () => homeCalls++);
      await m.initialize();
      clearInteractions(trips);
      c.add({'orderId': 'otro'});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verifyNever(trips.order(any));
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'cancelled'));
      c.add({'orderId': 'o1'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(homeCalls, 1);
      m.dispose();
      await c.close();
    });

    test('el cliente cambió la dirección: relee el pedido y avisa', () async {
      final c = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.orderAddressChanged).thenAnswer((_) => c.stream);
      final m = DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          pollInterval: const Duration(hours: 1),
          goHome: () => homeCalls++);
      await m.initialize();
      clearInteractions(trips);
      c.add({'orderId': 'otro'});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verifyNever(trips.order(any));
      expect(m.notice, isNull);
      c.add({'orderId': 'o1', 'message': 'cambió'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      verify(trips.order('o1')).called(1);
      expect(m.notice, contains('cambió la dirección'));
      m.dispose();
      await c.close();
    });

    test('lo entregó el cliente: corta tracking y sigue al cobro', () async {
      final m = build();
      await m.initialize();
      // La navegación deja el cobro arriba (lo que mira la pantalla).
      when(nav.currentRoute).thenReturn(Routes.paymentView);
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verify(socket.stopTracking()).called(1);
      verify(nav.replaceWithPaymentView(orderId: 'o1')).called(1);
      m.dispose();
    });

    test('sin timers vivos al salir: dispose frena el polling', () async {
      final m = build();
      await m.initialize();
      m.dispose();
      clearInteractions(trips);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verifyNever(trips.order(any));
    });
  });

  test('un fallo de red en el polling no rompe el pedido cargado', () async {
    final m = build();
    await m.initialize();
    when(trips.order('o1'))
        .thenThrow(DioException(requestOptions: RequestOptions(path: '')));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(m.order, isNotNull);
    expect(m.loadError, isNull);
    m.dispose();
  });

  test('DriverOrderStatus del pedido en camino', () {
    expect(DriverOrderStatus.parse('out_for_delivery'),
        DriverOrderStatus.onTheWay);
  });
}
