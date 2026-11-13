import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/core/config/app_config.dart';
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

  test('reject pega a su endpoint', () async {
    when(api.post(any, any, any, any)).thenAnswer((_) async => ok());
    await svc.reject('o1');
    verify(api.post('orders/o1/reject', any, 'tok', any)).called(1);
  });

  group('arrived (v2 con posición)', () {
    test('pega a /api/v2/orders/:id/arrived con latitude y longitude',
        () async {
      when(api.patch(any, any, any, any)).thenAnswer((_) async => ok());
      await svc.arrived('o1', latitude: -27.3575, longitude: -55.8904);
      verify(api.patch('${AppConfig.apiV2Url}orders/o1/arrived',
              {'latitude': -27.3575, 'longitude': -55.8904}, 'tok', any))
          .called(1);
    });

    test(
        'red caída: el reintento con la misma posición reusa la clave; con '
        'otra posición es otra clave', () async {
      final keys = <String>[];
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add(keyOf(i));
        if (keys.length == 1) throw offline();
        if (keys.length == 2) throw offline();
        return ok();
      });
      await expectLater(svc.arrived('o1', latitude: -27.1, longitude: -55.1),
          throwsA(isA<DioException>()));
      await expectLater(svc.arrived('o1', latitude: -27.1, longitude: -55.1),
          throwsA(isA<DioException>()));
      await svc.arrived('o1', latitude: -27.2, longitude: -55.1);
      expect(keys[0], keys[1]);
      expect(keys[2], isNot(keys[1]));
    });

    test('el 409 ARRIVAL_TOO_FAR se propaga y descarta la clave', () async {
      final keys = <String>[];
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add(keyOf(i));
        if (keys.length == 1) throw rejected(409);
        return ok();
      });
      await expectLater(svc.arrived('o1', latitude: -27.1, longitude: -55.1),
          throwsA(isA<DioException>()));
      await svc.arrived('o1', latitude: -27.1, longitude: -55.1);
      expect(keys[0], isNot(keys[1]));
    });
  });

  test('deliveryCode devuelve el texto del QR; sin código lanza', () async {
    when(api.get('orders/o1/delivery-code', 'tok'))
        .thenAnswer((_) async => ok({'orderId': 'o1', 'deliveryCode': 'A1B2'}));
    final info = await svc.deliveryCode('o1');
    expect(info.code, 'A1B2');
    expect(info.attempts, 0);
    expect(info.blocked, isFalse);
    when(api.get('orders/o3/delivery-code', 'tok')).thenAnswer((_) async => ok({
          'orderId': 'o3',
          'deliveryCode': '482913',
          'attempts': 5,
          'blocked': true
        }));
    final bloqueado = await svc.deliveryCode('o3');
    expect(bloqueado.attempts, 5);
    expect(bloqueado.blocked, isTrue);
    when(api.get('orders/o2/delivery-code', 'tok'))
        .thenAnswer((_) async => ok({'orderId': 'o2', 'deliveryCode': ''}));
    await expectLater(svc.deliveryCode('o2'), throwsA(isA<StateError>()));
  });

  test('regenerateDeliveryCode postea a la v2 y devuelve el código nuevo',
      () async {
    when(api.post(any, any, any, any)).thenAnswer(
        (_) async => ok({'orderId': 'o1', 'deliveryCode': '482913'}));
    expect(await svc.regenerateDeliveryCode('o1'), '482913');
    verify(api.post(
      argThat(endsWith('/api/v2/orders/o1/delivery-code/regenerate')),
      any,
      'tok',
      argThat(containsPair('Idempotency-Key', isNotEmpty)),
    )).called(1);
  });

  test('regenerateDeliveryCode sin código en la respuesta lanza', () async {
    when(api.post(any, any, any, any))
        .thenAnswer((_) async => ok({'orderId': 'o1'}));
    await expectLater(
        svc.regenerateDeliveryCode('o1'), throwsA(isA<StateError>()));
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
