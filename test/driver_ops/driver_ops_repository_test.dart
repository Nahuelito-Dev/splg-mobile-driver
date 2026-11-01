import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';

import '../helpers/test_helpers.mocks.dart';

Response _res(Object data, [int status = 200]) => Response(
    requestOptions: RequestOptions(path: ''), data: data, statusCode: status);

DioException _fail(int? status, [Object? data]) => DioException(
    requestOptions: RequestOptions(path: ''),
    response: status == null
        ? null
        : Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: status,
            data: data),
    type: status == null
        ? DioExceptionType.connectionError
        : DioExceptionType.badResponse);

Map<String, dynamic> _day({String? out}) => {
      'attendanceId': 'a1',
      'workDate': '2026-10-18',
      'checkInAt': '2026-10-18T11:00:00.000Z',
      'checkOutAt': out,
      'isOpen': out == null,
      'durationMinutes': out == null ? null : 480,
    };

void main() {
  late MockApiClient api;
  late MockDriverAuthService auth;
  late HttpDriverOpsRepository repo;

  Map<String, String> keyOf(Invocation i) =>
      i.positionalArguments[3] as Map<String, String>;

  setUp(() {
    api = MockApiClient();
    auth = MockDriverAuthService();
    when(auth.userId).thenReturn('u1');
    when(auth.token).thenAnswer((_) async => 'tok');
    repo = HttpDriverOpsRepository(api: api, auth: auth);
  });

  group('jornada', () {
    test(
        'checkIn y checkOut pegan a su ruta con Idempotency-Key y guardan la '
        'jornada', () async {
      when(api.post(HttpDriverOpsRepository.checkInPath, {}, 'tok', any))
          .thenAnswer((_) async => _res(_day(), 201));
      when(api.post(HttpDriverOpsRepository.checkOutPath, {}, 'tok', any))
          .thenAnswer((_) async => _res(_day(out: '2026-10-18T19:00:00.000Z')));
      expect(repo.workday, isNull);

      final w = await repo.checkIn();
      expect(w.isOpen, isTrue);
      expect(repo.workday!.isOpen, isTrue);
      final h = verify(api.post(
              HttpDriverOpsRepository.checkInPath, {}, 'tok', captureAny))
          .captured
          .single as Map<String, String>;
      expect(h['Idempotency-Key'], isNotEmpty);

      final out = await repo.checkOut();
      expect(out.isOpen, isFalse);
      expect(out.durationMinutes, 480);
      expect(repo.workday!.isOpen, isFalse);
    });

    test('la jornada no se arrastra a otra sesión', () async {
      when(api.post(HttpDriverOpsRepository.checkInPath, {}, 'tok', any))
          .thenAnswer((_) async => _res(_day()));
      await repo.checkIn();
      when(auth.userId).thenReturn('u2');
      expect(repo.workday, isNull);
    });

    test('currentWorkday lee la abierta (también de un día anterior) o 204',
        () async {
      when(api.get(HttpDriverOpsRepository.currentPath, 'tok'))
          .thenAnswer((_) async => _res({..._day(), 'workDate': '2026-10-16'}));
      final w = await repo.currentWorkday();
      expect(w!.isOpen, isTrue);
      expect(w.isFromPastDay(DateTime(2026, 10, 18)), isTrue);
      expect(repo.workday, same(w));

      when(api.get(HttpDriverOpsRepository.currentPath, 'tok'))
          .thenAnswer((_) async => _res('', 204));
      expect(await repo.currentWorkday(), isNull);
      expect(repo.workday, isNull);
    });

    test('sin respuesta reusa la clave; con un 409 de negocio la descarta',
        () async {
      final keys = <String>[];
      var n = 0;
      when(api.post(HttpDriverOpsRepository.checkOutPath, {}, 'tok', any))
          .thenAnswer((i) async {
        keys.add(keyOf(i)['Idempotency-Key']!);
        n++;
        if (n == 1) throw _fail(null);
        if (n == 2)
          throw _fail(409, {'message': 'No tenés una jornada abierta'});
        throw _fail(409, {'message': 'No tenés una jornada abierta'});
      });
      await expectLater(repo.checkOut(), throwsA(isA<DioException>()));
      await expectLater(repo.checkOut(), throwsA(isA<DioException>()));
      await expectLater(repo.checkOut(), throwsA(isA<DioException>()));
      expect(keys[1], keys[0], reason: 'tras la red caída reusa la clave');
      expect(keys[2], isNot(keys[1]), reason: 'tras el 409 pide una nueva');
    });
  });

  group('rendición', () {
    test('settlementPdf baja los bytes de la v2 con el token', () async {
      final bytes = Uint8List.fromList([37, 80, 68, 70]);
      when(api.getBytes(any, 'tok')).thenAnswer((_) async => bytes);
      expect(await repo.settlementPdf('s1'), bytes);
      final path = verify(api.getBytes(captureAny, 'tok')).captured.single;
      expect(path, endsWith('/api/v2/driver-settlements/s1/pdf'));
      expect(path, HttpDriverOpsRepository.settlementPdfPath('s1'));
    });

    test('previewSettlement consulta la v2 con el efectivo y los importes',
        () async {
      when(api.post(any, any, 'tok', any)).thenAnswer((_) async => _res({
            'expectedCash': 50000,
            'declaredCash': 46000,
            'driverExpenses': 3500,
            'difference': -500,
          }));
      final p = await repo
          .previewSettlement('s1', declaredCash: 46000, expenseAmounts: [3500]);
      expect(p.difference, -500);
      expect(p.expectedCash, 50000);
      final c = verify(api.post(captureAny, captureAny, 'tok', any)).captured;
      expect(c[0], HttpDriverOpsRepository.settlementPreviewPath('s1'));
      expect(c[0], endsWith('/api/v2/driver-settlements/s1/preview'));
      expect(c[1], {
        'declaredCash': 46000,
        'expenses': [
          {'amount': 3500}
        ],
      });
    });

    test('previewSettlement deja pasar el error del back', () async {
      when(api.post(any, any, 'tok', any))
          .thenAnswer((_) async => throw _fail(409, {'message': 'x'}));
      await expectLater(repo.previewSettlement('s1', declaredCash: 1),
          throwsA(isA<DioException>()));
    });

    test('settlementPdf deja pasar el error del back', () async {
      when(api.getBytes(any, 'tok'))
          .thenAnswer((_) async => throw _fail(403, {'message': 'No'}));
      await expectLater(repo.settlementPdf('s1'), throwsA(isA<DioException>()));
    });

    test('mySettlement lee con y sin fecha', () async {
      when(api.get('driver-settlements/mine', 'tok'))
          .thenAnswer((_) async => _res({
                'settlementId': 's1',
                'number': 7,
                'businessDate': '2026-10-18',
                'status': 'open',
                'expectedCash': 54000,
                'orders': [
                  {
                    'orderId': 'o1',
                    'customerName': 'Ana Gómez',
                    'deliveryAddress': 'Mitre 1200, Posadas',
                    'amountToCollect': 12000,
                    'paymentStatus': 'paid',
                    'deliveredAt': '2026-10-18T13:00:00Z'
                  }
                ],
                'collections': [
                  {'businessName': 'La Espiga', 'amount': 8000}
                ],
              }));
      final s = await repo.mySettlement();
      expect(s.id, 's1');
      expect(s.isOpen, isTrue);
      expect(s.expectedCash, 54000);
      expect(s.orders.single.amountToCollect, 12000);
      expect(s.orders.single.customerName, 'Ana Gómez');
      expect(s.orders.single.deliveryAddress, 'Mitre 1200, Posadas');
      expect(s.collections.single.businessName, 'La Espiga');

      when(api.get('driver-settlements/mine?date=2026-10-17', 'tok'))
          .thenAnswer((_) async => _res({'settlementId': 's0'}));
      expect((await repo.mySettlement(date: DateTime(2026, 10, 17))).id, 's0');
    });

    test('submitSettlement manda efectivo, gastos y notas', () async {
      when(api.post('driver-settlements/s1/submit', any, 'tok', any))
          .thenAnswer((_) async => _res({
                'settlementId': 's1',
                'status': 'submitted',
                'expectedCash': 54000,
                'declaredCash': 50000,
                'difference': -500,
              }));
      final s = await repo.submitSettlement('s1',
          declaredCash: 50000,
          expenses: const [
            ExpenseInput(categoryId: 'c1', amount: 3500, description: ' Nafta ')
          ],
          notes: ' ok ');
      expect(s.status, SettlementStatus.submitted);
      expect(s.difference, -500);
      final body = verify(
              api.post('driver-settlements/s1/submit', captureAny, 'tok', any))
          .captured
          .single as Map<String, dynamic>;
      expect(body, {
        'declaredCash': 50000,
        'expenses': [
          {'categoryId': 'c1', 'amount': 3500, 'description': 'Nafta'}
        ],
        'notes': 'ok',
      });
    });

    test('las categorías: las lee; si el back las niega, quedan vacías',
        () async {
      when(api.get(HttpDriverOpsRepository.categoriesPath, 'tok'))
          .thenAnswer((_) async => _res({
                'data': [
                  {
                    'categoryId': 'c1',
                    'name': 'Combustible',
                    'direction': 'expense',
                    'isActive': true,
                    'systemCode': null
                  },
                  {
                    'categoryId': 'c2',
                    'name': 'Compra',
                    'direction': 'expense',
                    'isActive': true,
                    'systemCode': 'purchase'
                  },
                  {
                    'categoryId': 'c3',
                    'name': 'Vieja',
                    'direction': 'expense',
                    'isActive': false,
                    'systemCode': null
                  },
                  {
                    'categoryId': 'c4',
                    'name': 'Ingreso',
                    'direction': 'income',
                    'isActive': true,
                    'systemCode': null
                  },
                ]
              }));
      final cats = await repo.expenseCategories();
      expect(cats.map((c) => c.name), ['Combustible'],
          reason: 'solo egresos activos y que no sean de sistema');
      when(api.get(HttpDriverOpsRepository.categoriesPath, 'tok'))
          .thenThrow(_fail(403, {'message': 'Forbidden resource'}));
      expect(await repo.expenseCategories(), isEmpty);
    });
  });

  test('registerFuelLoad arma el cuerpo del contrato y omite lo vacío',
      () async {
    when(api.post(HttpDriverOpsRepository.fuelPath, any, 'tok', any))
        .thenAnswer((_) async => _res({
              'carPatent': 'AB123CD',
              'liters': 40,
              'totalAmount': 42000,
              'odometerKm': 120350,
              'anomaly': true,
            }, 201));
    final r = await repo.registerFuelLoad(const FuelLoadInput(
      liters: 40,
      unitPrice: 1050,
      totalAmount: 42000,
      odometerKm: 120350,
      paymentMethod: FuelPayment.driverCash,
      station: 'YPF',
      receiptNumber: '  ',
    ));
    expect(r.anomaly, isTrue);
    expect(r.carPatent, 'AB123CD');
    final body = verify(
            api.post(HttpDriverOpsRepository.fuelPath, captureAny, 'tok', any))
        .captured
        .single as Map<String, dynamic>;
    expect(body, {
      'liters': 40,
      'unitPrice': 1050,
      'totalAmount': 42000,
      'odometerKm': 120350,
      'paymentMethod': 'driver_cash',
      'isFullTank': true,
      'station': 'YPF',
    });
  });

  test('reportAccident lee assignmentKept y su motivo', () async {
    when(api.post(HttpDriverOpsRepository.accidentPath, any, 'tok', any))
        .thenAnswer((_) async => _res({
              'vehicleUnusable': true,
              'carPatent': 'AB123CD',
              'assignmentKept': true,
              'assignmentKeptReason': 'Tenés un pedido en curso',
            }, 201));
    final r = await repo.reportAccident(AccidentInput(
        occurredAt: DateTime.utc(2026, 10, 18, 12),
        description: ' Choque ',
        vehicleUnusable: true,
        location: '-27.36,-55.89'));
    expect(r.assignmentKept, isTrue);
    expect(r.assignmentKeptReason, 'Tenés un pedido en curso');
    final body = verify(api.post(
            HttpDriverOpsRepository.accidentPath, captureAny, 'tok', any))
        .captured
        .single as Map<String, dynamic>;
    expect(body['occurredAt'], '2026-10-18T12:00:00.000Z');
    expect(body['description'], 'Choque');
    expect(body['vehicleUnusable'], true);
    expect(body['location'], '-27.36,-55.89');
    expect(body.containsKey('address'), isFalse);
  });

  test('la clave de la intención se manda tal cual y no cambia con el cuerpo',
      () async {
    when(api.post(HttpDriverOpsRepository.accidentPath, any, 'tok', any))
        .thenAnswer((_) async => _res({'vehicleUnusable': false}, 201));
    await repo.reportAccident(
        AccidentInput(occurredAt: DateTime.utc(2026), description: 'a'),
        idempotencyKey: 'k-1');
    final h = verify(api.post(
            HttpDriverOpsRepository.accidentPath, any, 'tok', captureAny))
        .captured
        .single as Map<String, String>;
    expect(h['Idempotency-Key'], 'k-1');
  });
}
