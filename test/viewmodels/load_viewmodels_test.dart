import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/views/deliveries/deliveries_viewmodel.dart';
import 'package:splg_driver/ui/views/earnings/earnings_viewmodel.dart';
import 'package:splg_driver/ui/views/profile/profile_viewmodel.dart';
import 'package:splg_driver/ui/views/rating/rating_viewmodel.dart';
import 'package:splg_driver/ui/views/vehicle/vehicle_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

DriverOrder order(String id, DateTime d,
        {DriverOrderStatus? s, num total = 100}) =>
    DriverOrder(
      id: id,
      status: s ?? DriverOrderStatus.delivered,
      total: total,
      createdAt: d,
    );

void main() {
  late MockDriverApiService api;

  setUp(() {
    registerServices();
    api = locator<DriverApiService>() as MockDriverApiService;
  });
  tearDown(() => locator.reset());

  group('DeliveriesViewModel', () {
    OrdersPage page(List<DriverOrder> o, {int? total, int offset = 0}) =>
        OrdersPage(orders: o, total: total ?? o.length, offset: offset);

    test('trae la primera página y conoce el total', () async {
      when(api.ordersPage(limit: 20)).thenAnswer((_) async => page([
            order('nuevo', DateTime(2026, 6, 1)),
            order('viejo', DateTime(2026, 1, 1)),
          ], total: 150));
      final m = DeliveriesViewModel();
      await m.load();
      expect(m.orders.map((o) => o.id), ['nuevo', 'viejo']);
      expect(m.total, 150);
      expect(m.hasMore, isTrue);
      expect(m.loadError, isNull);
    });

    test('loadMore agrega la página siguiente sin repetir pedidos', () async {
      when(api.ordersPage(limit: 20)).thenAnswer((_) async => page([
            order('a', DateTime(2026, 6, 3)),
            order('b', DateTime(2026, 6, 2)),
          ], total: 3));
      when(api.ordersPage(offset: 2, limit: 20)).thenAnswer((_) async => page(
          [order('b', DateTime(2026, 6, 2)), order('c', DateTime(2026, 6, 1))],
          total: 3, offset: 2));
      final m = DeliveriesViewModel();
      await m.load();
      await m.loadMore();
      expect(m.orders.map((o) => o.id), ['a', 'b', 'c']);
      expect(m.hasMore, isFalse);
      await m.loadMore();
      verify(api.ordersPage(offset: 2, limit: 20)).called(1);
    });

    test('si falla la carga de más expone el error y se puede reintentar',
        () async {
      when(api.ordersPage(limit: 20)).thenAnswer(
          (_) async => page([order('a', DateTime(2026, 6, 3))], total: 5));
      final m = DeliveriesViewModel();
      await m.load();
      when(api.ordersPage(offset: 1, limit: 20)).thenThrow(DioException(
          requestOptions: RequestOptions(path: 'x'),
          response: Response(
              requestOptions: RequestOptions(path: 'x'), statusCode: 500)));
      await m.loadMore();
      expect(m.moreError, ApiErrorText.server);
      expect(m.loadingMore, isFalse);
      when(api.ordersPage(offset: 1, limit: 20)).thenAnswer((_) async =>
          page([order('b', DateTime(2026, 6, 2))], total: 5, offset: 1));
      await m.loadMore(retry: true);
      expect(m.moreError, isNull);
      expect(m.orders, hasLength(2));
    });

    test('tras un error el scroll no reintenta solo: sólo con "Reintentar"',
        () async {
      when(api.ordersPage(limit: 20)).thenAnswer(
          (_) async => page([order('a', DateTime(2026, 6, 3))], total: 5));
      final m = DeliveriesViewModel();
      await m.load();
      when(api.ordersPage(offset: 1, limit: 20)).thenThrow(DioException(
          requestOptions: RequestOptions(path: 'x'),
          response: Response(
              requestOptions: RequestOptions(path: 'x'), statusCode: 500)));
      await m.loadMore();
      expect(m.moreError, isNotNull);

      // Eventos de scroll posteriores: no pegan al back.
      await m.loadMore();
      await m.loadMore();
      verify(api.ordersPage(offset: 1, limit: 20)).called(1);

      await m.loadMore(retry: true);
      verify(api.ordersPage(offset: 1, limit: 20)).called(1);
    });

    test(
        'pull-to-refresh con un loadMore en curso: se descarta la respuesta '
        'vieja y el offset sigue el del back', () async {
      List<DriverOrder> mk(int from, int n) => [
            for (var i = from; i < from + n; i++)
              order('o$i', DateTime(2026, 6, 1).subtract(Duration(hours: i))),
          ];
      when(api.ordersPage(limit: 20))
          .thenAnswer((_) async => page(mk(0, 20), total: 60));
      final slow = Completer<OrdersPage>();
      when(api.ordersPage(offset: 20, limit: 20))
          .thenAnswer((_) => slow.future);
      final m = DeliveriesViewModel();
      await m.load();

      final more = m.loadMore(); // en vuelo, offset 20
      await Future<void>.delayed(Duration.zero);
      await m.load(); // pull-to-refresh: nueva época
      expect(m.orders, hasLength(20));

      // Llega la respuesta vieja (con un hueco): se descarta.
      slow.complete(page(mk(25, 15), total: 60, offset: 20));
      await more;
      expect(m.orders, hasLength(20));
      expect(m.loadingMore, isFalse);

      // Y la lista sigue pidiendo el offset del back (20), no uno desfasado.
      when(api.ordersPage(offset: 20, limit: 20))
          .thenAnswer((_) async => page(mk(20, 20), total: 60, offset: 20));
      await m.loadMore();
      expect(m.orders, hasLength(40));
      verify(api.ordersPage(offset: 20, limit: 20)).called(2);
    });

    test('con repetidos entre páginas el offset no se desfasa', () async {
      when(api.ordersPage(limit: 20)).thenAnswer((_) async => page([
            order('a', DateTime(2026, 6, 3)),
            order('b', DateTime(2026, 6, 2)),
          ], total: 6));
      // La página 2 repite "b": quedan 3 dedupicados, pero el back avanzó 4.
      when(api.ordersPage(offset: 2, limit: 20)).thenAnswer((_) async => page([
            order('b', DateTime(2026, 6, 2)),
            order('c', DateTime(2026, 6, 1)),
          ], total: 6, offset: 2));
      when(api.ordersPage(offset: 4, limit: 20)).thenAnswer((_) async => page([
            order('d', DateTime(2026, 5, 31)),
            order('e', DateTime(2026, 5, 30)),
          ], total: 6, offset: 4));
      final m = DeliveriesViewModel();
      await m.load();
      await m.loadMore();
      await m.loadMore();

      expect(m.orders.map((o) => o.id), ['a', 'b', 'c', 'd', 'e']);
      verify(api.ordersPage(offset: 4, limit: 20)).called(1);
      expect(m.hasMore, isFalse);
    });

    test('sin entregas queda vacío', () async {
      when(api.ordersPage(limit: 20)).thenAnswer((_) async => page([]));
      final m = DeliveriesViewModel();
      await m.load();
      expect(m.orders, isEmpty);
      expect(m.hasMore, isFalse);
    });

    test('si el back falla expone un texto propio y se puede reintentar',
        () async {
      when(api.ordersPage(limit: 20)).thenThrow(DioException(
        requestOptions: RequestOptions(path: 'x'),
        response: Response(
          requestOptions: RequestOptions(path: 'x'),
          statusCode: 403,
          data: {'message': 'Forbidden resource'},
        ),
      ));
      final m = DeliveriesViewModel();
      await m.load();
      expect(m.loadError, ApiErrorText.forbidden);

      when(api.ordersPage(limit: 20)).thenAnswer((_) async => page([]));
      await m.load();
      expect(m.loadError, isNull);
    });
  });

  test('VehicleViewModel guarda el vehículo (o null)', () async {
    when(api.vehicle()).thenAnswer((_) async => null);
    final m = VehicleViewModel();
    await m.load();
    expect(m.vehicle, isNull);

    when(api.vehicle()).thenAnswer((_) async => const DriverVehicle(
        brand: 'Fiat', model: 'Fiorino', patent: 'AF123SP'));
    await m.load();
    expect(m.vehicle!.patent, 'AF123SP');
  });

  test('RatingViewModel trae el resumen', () async {
    when(api.rating())
        .thenAnswer((_) async => const RatingSummary(average: 4.5, count: 2));
    final m = RatingViewModel();
    await m.load();
    expect(m.summary!.count, 2);
  });

  test('EarningsViewModel calcula con el reloj inyectado', () async {
    when(api.orders()).thenAnswer((_) async => [
          order('a', DateTime(2026, 10, 10, 9), total: 700),
          order('b', DateTime(2026, 10, 9, 9), total: 300),
        ]);
    final m = EarningsViewModel()..now = () => DateTime(2026, 10, 10, 20);
    await m.load();
    expect(m.summary!.today, 700);
    expect(m.summary!.week, 1000);
  });

  group('ProfileViewModel', () {
    const profile = DriverProfile(userId: 'u', fullName: 'Chofer Prueba');

    test('carga perfil y foto; las iniciales salen del nombre', () async {
      when(api.profile(refresh: true)).thenAnswer((_) async => profile);
      when(api.photoUrl()).thenAnswer((_) async => 'https://s3/x.jpg');
      final m = ProfileViewModel();
      await m.load();
      expect(m.photoUrl, 'https://s3/x.jpg');
      expect(m.initials, 'CP');
    });

    test('si la foto falla igual muestra el perfil', () async {
      when(api.profile(refresh: true)).thenAnswer((_) async => profile);
      when(api.photoUrl()).thenThrow(Exception('s3'));
      final m = ProfileViewModel();
      await m.load();
      expect(m.loadError, isNull);
      expect(m.photoUrl, isNull);
    });
  });
}
