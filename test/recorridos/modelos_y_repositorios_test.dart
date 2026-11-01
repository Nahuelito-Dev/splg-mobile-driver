import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/services/recovery_repository.dart';
import 'package:splg_driver/services/route_batch_repository.dart';

import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

void main() {
  group('RouteBatch', () {
    test('lee el contrato: oferta, paradas activas en orden y totales', () {
      final b = RouteBatch.fromJson(batchJson(stops: [
        stopJson('o2', 2),
        stopJson('o1', 1),
        stopJson('o3', 3, active: false),
      ]));
      expect(b.batchId, 'b1');
      expect(b.totalWeightKg, 75.5);
      expect(b.awaitsAnswer, true);
      expect([for (final s in b.stops) s.orderId], ['o1', 'o2']);
      expect(b.stops.first.slotText, 'Mañana 08:00 a 12:00');
      expect(b.stops.first.address, 'Av. Corrientes 1234, Posadas');
      expect(b.stops.first.itemsText, '2 x Garrafa 10 kg');
      expect(b.totalDistanceKm, 1.5);
    });

    test('una parada sin dirección formateada arma la dirección con la calle',
        () {
      final j = stopJson('o1', 1);
      (j['address'] as Map)['formattedAddress'] = null;
      (j['address'] as Map)['floor'] = '2';
      expect(RouteBatchStop.fromJson(j).address,
          'Av. Corrientes 1234, piso 2, Posadas');
    });

    test('un lote sin oferta pendiente no espera respuesta', () {
      expect(
          RouteBatch.fromJson(batchJson(offerStatus: 'expired')).awaitsAnswer,
          false);
      expect(RouteBatch.fromJson(batchJson(status: 'assigned')).awaitsAnswer,
          false);
      expect(RouteBatch.fromJson({'batchId': 'x'}).offer, isNull);
    });

    test('la oferta cuenta lo que falta y nunca baja de cero', () {
      final b = batch(ttl: const Duration(seconds: 30));
      final left = b.offer!.remaining(DateTime.now()).inSeconds;
      expect(left, inInclusiveRange(28, 30));
      expect(b.offer!.remaining(DateTime.now().add(const Duration(minutes: 5))),
          Duration.zero);
    });

    test('los avisos del socket se leen por evento', () {
      final offered = parseRouteBatchEvent('route-batch:offer', {
        'batchId': 'b1',
        'offerId': 'of1',
        'expiresAt': '2026-11-03T12:00:00.000Z',
        'totalWeightKg': 50,
        'stopCount': 2,
      });
      expect(offered, isA<RouteBatchOffered>());
      expect((offered as RouteBatchOffered).expiresAt, isNotNull);
      final closed = parseRouteBatchEvent(
          'route-batch:offer-closed', {'batchId': 'b1', 'reason': 'expired'});
      expect((closed as RouteBatchClosed).reason, 'expired');
      final assigned = parseRouteBatchEvent('route-batch:assigned', {
        'batchId': 'b1',
        'orderIds': ['o1', 'o2']
      });
      expect((assigned as RouteBatchAssigned).orderIds, ['o1', 'o2']);
      expect(parseRouteBatchEvent('route-batch:offer', {}), isNull);
      expect(parseRouteBatchEvent('otro', {'batchId': 'b1'}), isNull);
    });
  });

  group('HttpRouteBatchRepository', () {
    late MockApiClient api;
    late MockDriverAuthService auth;
    late HttpRouteBatchRepository repo;

    setUp(() {
      api = MockApiClient();
      auth = MockDriverAuthService();
      when(auth.token).thenAnswer((_) async => 'tok');
      repo = HttpRouteBatchRepository(api: api, auth: auth);
    });

    test('mine lee la página {data,total} de la v2', () async {
      when(api.get(
              '${HttpRouteBatchRepository.basePath}?limit=20&offset=0', 'tok'))
          .thenAnswer((_) async => res({
                'data': [batchJson()],
                'total': 1
              }));
      final list = await repo.mine();
      expect(list.single.batchId, 'b1');
      expect(HttpRouteBatchRepository.basePath, contains('/api/v2/'));
    });

    test('batch lee el detalle', () async {
      when(api.get(HttpRouteBatchRepository.batchPath('b1'), 'tok'))
          .thenAnswer((_) async => res(batchJson()));
      expect((await repo.batch('b1')).stops, hasLength(2));
    });

    test('accept manda el POST con Idempotency-Key y lee la decisión',
        () async {
      when(api.post(HttpRouteBatchRepository.acceptPath('b1'), {}, 'tok', any))
          .thenAnswer((_) async => res(
              {'batchId': 'b1', 'accepted': true, 'assignedOrders': 2}, 201));
      final d = await repo.accept('b1');
      expect(d.accepted, true);
      expect(d.assignedOrders, 2);
      final key = (verify(api.post(any, any, any, captureAny)).captured.single
          as Map<String, String>)['Idempotency-Key'];
      expect(key, isNotEmpty);
    });

    test('sin respuesta reusa la clave; con un 409 de negocio la descarta',
        () async {
      final path = HttpRouteBatchRepository.acceptPath('b1');
      final keys = <String>[];
      var n = 0;
      when(api.post(path, {}, 'tok', any)).thenAnswer((i) async {
        keys.add((i.positionalArguments[3] as Map)['Idempotency-Key']);
        n++;
        if (n == 1) throw http(null);
        if (n == 2) throw http(409, {'message': 'La oferta del lote venció'});
        return res({'batchId': 'b1', 'accepted': true, 'assignedOrders': 1});
      });
      await expectLater(repo.accept('b1'), throwsA(isA<DioException>()));
      await expectLater(repo.accept('b1'), throwsA(isA<DioException>()));
      expect(keys[1], keys[0]);
      await repo.accept('b1');
      expect(keys[2], isNot(keys[0]));
    });

    test('reject pega a su ruta', () async {
      when(api.post(HttpRouteBatchRepository.rejectPath('b1'), {}, 'tok', any))
          .thenAnswer((_) async => res(
              {'batchId': 'b1', 'accepted': false, 'assignedOrders': 0}, 201));
      expect((await repo.reject('b1')).accepted, false);
    });

    test('sin sesión no pide nada', () async {
      when(auth.token).thenAnswer((_) async => null);
      await expectLater(repo.batch('b1'), throwsStateError);
      verifyNever(api.get(any, any));
    });
  });

  group('HttpRecoveryRepository', () {
    late MockApiClient api;
    late MockDriverAuthService auth;
    late HttpRecoveryRepository repo;

    setUp(() {
      api = MockApiClient();
      auth = MockDriverAuthService();
      when(auth.token).thenAnswer((_) async => 'tok');
      repo = HttpRecoveryRepository(api: api, auth: auth);
    });

    test('pickups lee el arreglo de retiros', () async {
      when(api.get(HttpRecoveryRepository.basePath, 'tok'))
          .thenAnswer((_) async => res([pickupJson()]));
      final list = await repo.pickups();
      expect(list.single.serial, 'SPLG-00042');
      expect(list.single.depositAmount, 25000);
      expect(HttpRecoveryRepository.basePath,
          endsWith('/api/v2/cylinder-recovery/driver/pickups'));
    });

    test('con el módulo apagado la lista es vacía', () async {
      when(api.get(HttpRecoveryRepository.basePath, 'tok'))
          .thenAnswer((_) async => res([]));
      expect(await repo.pickups(), isEmpty);
    });

    test('confirm pega a su ruta con Idempotency-Key', () async {
      when(api.post(HttpRecoveryRepository.confirmPath('n1'), {}, 'tok', any))
          .thenAnswer((_) async => res({'caseId': 'c1', 'status': 'returned'}));
      await repo.confirm('n1');
      verify(api.post(HttpRecoveryRepository.confirmPath('n1'), {}, 'tok',
              argThat(containsPair('Idempotency-Key', isNotEmpty))))
          .called(1);
    });

    test('notCollected manda el motivo sin espacios sobrantes', () async {
      when(api.post(HttpRecoveryRepository.notCollectedPath('n1'),
              {'reason': 'No estaba'}, 'tok', any))
          .thenAnswer((_) async => res({'caseId': 'c1', 'status': 'open'}));
      await repo.notCollected('n1', reason: '  No estaba ');
      verify(api.post(HttpRecoveryRepository.notCollectedPath('n1'),
              {'reason': 'No estaba'}, 'tok', any))
          .called(1);
    });
  });
}
