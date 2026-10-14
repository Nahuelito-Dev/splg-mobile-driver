import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.mocks.dart';

Map<String, dynamic> _order(int i) => {
      'order_id': 'o$i',
      'status': 'delivered',
      'total_amount': 100,
      'created_at': DateTime(2026, 10, 10, 9).toIso8601String(),
    };

Response _res(Object data, [int status = 200]) => Response(
    requestOptions: RequestOptions(path: ''), data: data, statusCode: status);

void main() {
  late MockApiClient api;
  late MockDriverAuthService auth;
  late DriverApiService service;

  setUp(() {
    api = MockApiClient();
    auth = MockDriverAuthService();
    when(auth.userId).thenReturn('u1');
    when(auth.token).thenAnswer((_) async => 'tok');
    when(api.get('users/u1', 'tok')).thenAnswer((_) async => _res({
          'user_id': 'u1',
          'full_name': 'Chofer',
          'delivery': {'delivery_id': 'd1'},
        }));
    service = DriverApiService(api: api, auth: auth);
  });

  group('historial paginado', () {
    test('orders() recorre las páginas hasta el total (más de 100 pedidos)',
        () async {
      const total = 250;
      for (final offset in [0, 100, 200]) {
        final n = (total - offset).clamp(0, 100);
        when(api.get('orders/delivery/d1?limit=100&offset=$offset', 'tok'))
            .thenAnswer((_) async => _res({
                  'orders': [for (var i = 0; i < n; i++) _order(offset + i)],
                  'total': total,
                }));
      }

      final all = await service.orders();

      expect(all, hasLength(250));
      expect({for (final o in all) o.id}, hasLength(250));
      verify(api.get('orders/delivery/d1?limit=100&offset=100', 'tok'))
          .called(1);
      verify(api.get('orders/delivery/d1?limit=100&offset=200', 'tok'))
          .called(1);
      // Las estadísticas "totales" cuentan los 250, no sólo los últimos 100.
      expect(EarningsSummary.from(all, DateTime(2026, 10, 10, 20)).totalCount,
          250);
    });

    test('ordersPage lee total y offset del back', () async {
      when(api.get('orders/delivery/d1?limit=20&offset=20', 'tok'))
          .thenAnswer((_) async => _res({
                'orders': [for (var i = 0; i < 20; i++) _order(20 + i)],
                'total': 45,
              }));

      final page = await service.ordersPage(offset: 20, limit: 20);

      expect(page.total, 45);
      expect(page.nextOffset, 40);
      expect(page.hasMore, isTrue);
    });

    test('si el back devuelve una página vacía no entra en loop', () async {
      when(api.get(any, 'tok')).thenAnswer((_) async => _res({
            'orders': [],
            'total': 999,
          }));
      final all = await service.orders();
      expect(all, isEmpty);
    });
  });

  group('activeOrder', () {
    test('lee el pedido en curso de GET orders/delivery/me/active', () async {
      when(api.get('orders/delivery/me/active', 'tok'))
          .thenAnswer((_) async => _res({..._order(7), 'status': 'accepted'}));
      final o = await service.activeOrder();
      expect(o!.id, 'o7');
      expect(o.status, DriverOrderStatus.accepted);
    });

    test('204 sin cuerpo: no hay nada que retomar', () async {
      when(api.get('orders/delivery/me/active', 'tok'))
          .thenAnswer((_) async => _res('', 204));
      expect(await service.activeOrder(), isNull);
    });
  });

  group('errorMessage', () {
    DioException err(int? status, [Object? data]) => DioException(
          requestOptions: RequestOptions(path: ''),
          response: status == null ? null : _res(data ?? {}, status),
        );

    test('texto propio por código y mensaje de negocio sólo en 400/409', () {
      expect(DriverApiService.errorMessage(err(null)), ApiErrorText.offline);
      expect(
          DriverApiService.errorMessage(err(401)), ApiErrorText.sessionExpired);
      expect(
          DriverApiService.errorMessage(
              err(403, {'message': 'Forbidden resource'})),
          ApiErrorText.forbidden);
      expect(DriverApiService.errorMessage(err(404)), ApiErrorText.notFound);
      expect(DriverApiService.errorMessage(err(429)), ApiErrorText.tooMany);
      expect(
          DriverApiService.errorMessage(
              err(500, {'message': 'Internal server error'})),
          ApiErrorText.server);
      expect(
          DriverApiService.errorMessage(
              err(400, {'message': 'El chofer no tiene un vehículo asignado'})),
          'El chofer no tiene un vehículo asignado');
      expect(
          DriverApiService.errorMessage(err(400, {
            'message': 'delivery 3f2b8c1e-0a4d-4c3e-9b1a-2d5e6f708192 not found'
          })),
          ApiErrorText.generic);
    });
  });
}
