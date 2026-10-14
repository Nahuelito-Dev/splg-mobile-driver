import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
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
  late int homeCalls;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    dialogs = locator<DialogService>() as MockDialogService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
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
      when(trips.arrived('o1')).thenAnswer((_) async {});
      await m.arriveAndDeliver();
      await m.arriveAndDeliver();
      verify(trips.arrived('o1')).called(1);
      verify(nav.navigateToDeliveryQrView(orderId: 'o1')).called(2);
      m.dispose();
    });

    test('llegué: si el aviso falla no abre el QR', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      final m = build();
      await m.initialize();
      when(trips.arrived('o1')).thenThrow(rejected());
      await m.arriveAndDeliver();
      expect(m.errorMessage, isNotNull);
      expect(m.arrivedNotified, false);
      verifyNever(nav.navigateToDeliveryQrView(orderId: 'o1'));
      m.dispose();
    });

    test('llegué sólo vale en camino', () async {
      final m = build();
      await m.initialize();
      await m.arriveAndDeliver();
      verifyNever(trips.arrived(any));
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

    test('lo entregó el cliente: corta tracking y sigue al cobro', () async {
      final m = build();
      await m.initialize();
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
