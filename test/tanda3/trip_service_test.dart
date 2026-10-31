import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/services/trip_service.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

void main() {
  late MockApiClient api;
  late MockDriverAuthService auth;
  late TripService svc;

  setUp(() {
    registerServices();
    api = MockApiClient();
    auth = MockDriverAuthService();
    when(auth.token).thenAnswer((_) async => 'tok');
    svc = TripService(api: api, auth: auth);
  });

  Response ok([dynamic data]) => Response(
      requestOptions: RequestOptions(path: ''), data: data, statusCode: 200);
  DioException offline() =>
      DioException(requestOptions: RequestOptions(path: ''));
  DioException rejected(int code) => DioException(
      requestOptions: RequestOptions(path: ''),
      response:
          Response(requestOptions: RequestOptions(path: ''), statusCode: code));

  String keyOf(Invocation i) =>
      (i.positionalArguments[3] as Map<String, String>)['Idempotency-Key']!;

  group('Idempotency-Key', () {
    test('con la red caída el reintento reusa la misma clave', () async {
      final keys = <String>[];
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add(keyOf(i));
        if (keys.length == 1) throw offline();
        return ok();
      });
      await expectLater(
          svc.setStatus('o1', 'on_the_way'), throwsA(isA<DioException>()));
      await svc.setStatus('o1', 'on_the_way');
      expect(keys[0], keys[1]);
    });

    test('tras una respuesta del back la clave se descarta', () async {
      final keys = <String>[];
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add(keyOf(i));
        if (keys.length == 1) throw rejected(400);
        return ok();
      });
      await expectLater(
          svc.setStatus('o1', 'accepted'), throwsA(isA<DioException>()));
      await svc.setStatus('o1', 'accepted');
      expect(keys[0], isNot(keys[1]));
    });

    test('acciones distintas llevan claves distintas', () async {
      final keys = <String>[];
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add(keyOf(i));
        return ok();
      });
      await svc.setStatus('o1', 'accepted');
      await svc.setStatus('o1', 'on_the_way');
      expect(keys[0], isNot(keys[1]));
    });
  });

  test('setStatus manda el valor del enum del back', () async {
    when(api.patch(any, any, any, any)).thenAnswer((_) async => ok());
    await svc.setStatus('o1', 'on_the_way');
    verify(api.patch('orders/o1/status', {'status': 'on_the_way'}, 'tok', any))
        .called(1);
  });

  test('reject y arrived pegan a sus endpoints', () async {
    when(api.post(any, any, any, any)).thenAnswer((_) async => ok());
    when(api.patch(any, any, any, any)).thenAnswer((_) async => ok());
    await svc.reject('o1');
    await svc.arrived('o1');
    verify(api.post('orders/o1/reject', any, 'tok', any)).called(1);
    verify(api.patch('orders/o1/arrived', any, 'tok', any)).called(1);
  });

  test('deliveryCode devuelve el texto del QR; sin código lanza', () async {
    when(api.get('orders/o1/delivery-code', 'tok'))
        .thenAnswer((_) async => ok({'orderId': 'o1', 'deliveryCode': 'A1B2'}));
    expect(await svc.deliveryCode('o1'), 'A1B2');
    when(api.get('orders/o2/delivery-code', 'tok'))
        .thenAnswer((_) async => ok({'orderId': 'o2', 'deliveryCode': ''}));
    await expectLater(svc.deliveryCode('o2'), throwsA(isA<StateError>()));
  });

  test('rateCustomer manda orderId, stars y comentario sin espacios', () async {
    when(api.post(any, any, any, any)).thenAnswer((_) async => ok());
    await svc.rateCustomer('o1', 4, '  Bien  ');
    verify(api.post('ratings', {'orderId': 'o1', 'stars': 4, 'comment': 'Bien'},
            'tok', any))
        .called(1);
    await svc.rateCustomer('o2', 5, '   ');
    verify(api.post('ratings', {'orderId': 'o2', 'stars': 5}, 'tok', any))
        .called(1);
  });

  test('order parsea la respuesta; customerRating devuelve null si falla',
      () async {
    when(api.get('orders/o1', 'tok')).thenAnswer((_) async => ok(orderJson()));
    expect((await svc.order('o1')).customerName, 'Cliente Prueba');
    when(api.get('ratings/user/c1/summary', 'tok')).thenThrow(offline());
    expect(await svc.customerRating('c1'), isNull);
  });

  test('sin sesión lanza en vez de llamar', () async {
    when(auth.token).thenAnswer((_) async => null);
    await expectLater(svc.order('o1'), throwsA(isA<StateError>()));
    verifyNever(api.get(any, any));
  });
}
