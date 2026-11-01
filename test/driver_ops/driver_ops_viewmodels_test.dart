import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/ui/common/amount_input.dart';
import 'package:splg_driver/ui/views/accident/accident_viewmodel.dart';
import 'package:splg_driver/ui/views/fuel_load/fuel_load_viewmodel.dart';
import 'package:splg_driver/ui/views/settlement/settlement_viewmodel.dart';
import 'package:splg_driver/ui/views/workday/workday_viewmodel.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

DioException _fail(int status, String message) => DioException(
    requestOptions: RequestOptions(path: ''),
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: status,
        data: {'message': message}));

Workday _w({DateTime? out}) => Workday(
    id: 'a1',
    workDate: '2026-10-18',
    checkInAt: DateTime(2026, 10, 18, 8, 12),
    checkOutAt: out,
    durationMinutes: out == null ? null : 480);

Settlement _s({SettlementStatus status = SettlementStatus.open}) => Settlement(
    id: 's1',
    number: 3,
    businessDate: '2026-10-18',
    status: status,
    expectedCash: 50000);

void main() {
  late MockDriverOpsRepository ops;

  setUp(() {
    registerServices();
    ops = locator<DriverOpsRepository>() as MockDriverOpsRepository;
  });
  tearDown(() => locator.reset());

  group('parseAmount', () {
    test('formato argentino: punto = miles, coma = decimales', () {
      expect(parseAmount('1.500'), 1500);
      expect(parseAmount('1500,50'), 1500.5);
      expect(parseAmount('40,5'), 40.5);
      expect(parseAmount('1.234.567,89'), 1234567.89);
      expect(parseAmount(r'$ 1.500'), 1500);
      expect(parseAmount('0'), 0);
      expect(parseAmount('42.5'), isNull, reason: 'el punto es de miles');
      expect(parseAmount('1.50'), isNull);
      expect(parseAmount('1,234', maxDecimals: 2), isNull);
      expect(parseAmount('1,234', maxDecimals: 3), 1.234);
      expect(parseAmount('12,5', maxDecimals: 0), isNull);
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
    });
  });

  group('WorkdayViewModel', () {
    final today = DateTime(2026, 10, 18, 10);

    test('iniciar guarda la jornada abierta; finalizar la cierra', () async {
      Workday? current;
      when(ops.workday).thenAnswer((_) => current);
      when(ops.currentWorkday()).thenAnswer((_) async => current);
      when(ops.checkIn()).thenAnswer((_) async => current = _w());
      when(ops.checkOut()).thenAnswer(
          (_) async => current = _w(out: DateTime(2026, 10, 18, 16)));
      final m = WorkdayViewModel()..now = () => today;
      await m.load();
      expect(m.isOpen, isFalse);
      expect(m.canStart, isTrue);
      await m.start();
      expect(m.isOpen, isTrue);
      expect(m.canFinish, isTrue);
      expect(m.failure, isNull);
      await m.finish();
      expect(m.isOpen, isFalse);
      expect(m.needsRestartConfirmation, isTrue,
          reason: 'ya cerró una jornada hoy');
      verifyInOrder([ops.checkIn(), ops.checkOut()]);
    });

    test('abierta de un día anterior: sin botones y a corregir en el panel',
        () async {
      final old = Workday(
          id: 'a0',
          workDate: '2026-10-16',
          checkInAt: DateTime(2026, 10, 16, 8));
      when(ops.workday).thenReturn(old);
      when(ops.currentWorkday()).thenAnswer((_) async => old);
      final m = WorkdayViewModel()..now = () => today;
      await m.load();
      expect(m.isStale, isTrue);
      expect(m.canFinish, isFalse);
      expect(m.canStart, isFalse);
    });

    test('abierta de hoy cargada desde el panel: se puede finalizar', () async {
      final w = _w();
      when(ops.workday).thenReturn(w);
      when(ops.currentWorkday()).thenAnswer((_) async => w);
      final m = WorkdayViewModel()..now = () => today;
      await m.load();
      expect(m.isStale, isFalse);
      expect(m.canFinish, isTrue);
    });

    test('el 409 real del check-in (ya hay una abierta) relee y no es error',
        () async {
      Workday? current;
      when(ops.workday).thenAnswer((_) => current);
      when(ops.checkIn()).thenAnswer((_) async => throw _fail(409,
          'El empleado ya tiene una jornada abierta: cerrala antes de abrir otra'));
      when(ops.currentWorkday()).thenAnswer((_) async => current = _w());
      final m = WorkdayViewModel()..now = () => today;
      await m.start();
      verify(ops.currentWorkday()).called(1);
      expect(m.isOpen, isTrue);
      expect(m.failure, isNull);
    });

    test('un 409 que no es "ya abierta" se muestra aunque relea', () async {
      when(ops.workday).thenReturn(null);
      when(ops.currentWorkday()).thenAnswer((_) async => null);
      when(ops.checkOut()).thenAnswer(
          (_) async => throw _fail(409, 'No tenés una jornada abierta'));
      final m = WorkdayViewModel()..now = () => today;
      await m.finish();
      verify(ops.currentWorkday()).called(1);
      expect(m.failure, contains('No tenés una jornada abierta'));
    });

    test('sin red avisa sin conexión', () async {
      when(ops.workday).thenReturn(null);
      when(ops.checkOut()).thenAnswer((_) async => throw DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError));
      final m = WorkdayViewModel();
      await m.finish();
      expect(m.failure, contains('Sin conexión'));
    });
  });

  group('SettlementViewModel', () {
    test('carga la rendición y las categorías si está abierta', () async {
      when(ops.mySettlement()).thenAnswer((_) async => _s());
      when(ops.expenseCategories()).thenAnswer(
          (_) async => const [ExpenseCategory(id: 'c1', name: 'Combustible')]);
      final m = SettlementViewModel();
      await m.load();
      expect(m.settlement!.expectedCash, 50000);
      expect(m.canDeclareExpenses, isTrue);
      expect(m.isEditable, isTrue);
    });

    test(
        'baja el PDF de la rendición y lo comparte, también si no es la abierta',
        () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(ops.mySettlement())
          .thenAnswer((_) async => _s(status: SettlementStatus.approved));
      when(ops.settlementPdf('s1')).thenAnswer((_) async => bytes);
      Uint8List? sent;
      String? name;
      final m = SettlementViewModel(sharePdf: (b, f) async {
        sent = b;
        name = f;
        return true;
      });
      expect(m.canDownloadPdf, isFalse, reason: 'sin rendición cargada');
      await m.load();
      expect(m.canDownloadPdf, isTrue);
      await m.downloadPdf();
      expect(sent, bytes);
      expect(name, 'rendicion-3.pdf');
      expect(m.pdfError, isNull);
      expect(m.downloadingPdf, isFalse);
    });

    test('mientras baja el PDF queda deshabilitado', () async {
      final c = Completer<Uint8List>();
      when(ops.mySettlement()).thenAnswer((_) async => _s());
      when(ops.expenseCategories()).thenAnswer((_) async => const []);
      when(ops.settlementPdf('s1')).thenAnswer((_) => c.future);
      final m = SettlementViewModel(sharePdf: (b, f) async => true);
      await m.load();
      final f = m.downloadPdf();
      expect(m.downloadingPdf, isTrue);
      expect(m.canDownloadPdf, isFalse);
      c.complete(Uint8List(1));
      await f;
      expect(m.canDownloadPdf, isTrue);
    });

    test('si el back rechaza el PDF muestra su mensaje y no comparte',
        () async {
      when(ops.mySettlement()).thenAnswer((_) async => _s());
      when(ops.expenseCategories()).thenAnswer((_) async => const []);
      when(ops.settlementPdf('s1'))
          .thenAnswer((_) async => throw _fail(409, 'No es tu rendición'));
      var shared = false;
      final m = SettlementViewModel(sharePdf: (b, f) async => shared = true);
      await m.load();
      await m.downloadPdf();
      expect(shared, isFalse);
      expect(m.pdfError, contains('No es tu rendición'));
      expect(m.canDownloadPdf, isTrue);
    });

    test('presentada no pide categorías y no es editable', () async {
      when(ops.mySettlement())
          .thenAnswer((_) async => _s(status: SettlementStatus.submitted));
      final m = SettlementViewModel();
      await m.load();
      expect(m.isEditable, isFalse);
      expect(m.canSubmit, isFalse);
      verifyNever(ops.expenseCategories());
    });

    test('un error de lectura queda en loadError', () async {
      when(ops.mySettlement()).thenAnswer((_) async => throw _fail(404, 'x'));
      final m = SettlementViewModel();
      await m.load();
      expect(m.loadError, isNotNull);
    });

    test('valida y presenta con efectivo y gastos; muestra la diferencia',
        () async {
      when(ops.mySettlement()).thenAnswer((_) async => _s());
      when(ops.expenseCategories()).thenAnswer(
          (_) async => const [ExpenseCategory(id: 'c1', name: 'Combustible')]);
      when(ops.submitSettlement('s1',
              declaredCash: anyNamed('declaredCash'),
              expenses: anyNamed('expenses'),
              notes: anyNamed('notes'),
              idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((_) async => _s(status: SettlementStatus.submitted));
      final m = SettlementViewModel(previewDebounce: Duration.zero);
      await m.load();
      expect(m.canSubmit, isFalse, reason: 'sin efectivo');

      m.setDeclaredCash('46.000');
      expect(m.canSubmit, isTrue);
      m.addExpense();
      expect(m.canSubmit, isFalse, reason: 'gasto sin categoría ni importe');
      m.updateExpense(m.expenses.single, categoryId: 'c1', amount: '3500');
      expect(m.canSubmit, isTrue);

      await m.submit();
      final call = verify(ops.submitSettlement('s1',
              declaredCash: captureAnyNamed('declaredCash'),
              expenses: captureAnyNamed('expenses'),
              notes: captureAnyNamed('notes'),
              idempotencyKey: anyNamed('idempotencyKey')))
          .captured;
      expect(call[0], 46000);
      expect((call[1] as List<ExpenseInput>).single.amount, 3500);
      expect(m.settlement!.status, SettlementStatus.submitted);
      expect(m.submitError, isNull);
    });

    test('un 409 al presentar se muestra y la rendición sigue abierta',
        () async {
      when(ops.mySettlement()).thenAnswer((_) async => _s());
      when(ops.expenseCategories()).thenAnswer((_) async => const []);
      when(ops.submitSettlement('s1',
              declaredCash: anyNamed('declaredCash'),
              expenses: anyNamed('expenses'),
              notes: anyNamed('notes'),
              idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((_) async =>
              throw _fail(409, 'La rendición no está abierta para presentar'));
      final m = SettlementViewModel();
      await m.load();
      m.setDeclaredCash('0');
      await m.submit();
      expect(m.submitError, contains('no está abierta'));
      expect(m.isEditable, isTrue);
      expect(m.submitting, isFalse);
    });

    test('efectivo negativo no se presenta', () async {
      when(ops.mySettlement()).thenAnswer((_) async => _s());
      when(ops.expenseCategories()).thenAnswer((_) async => const []);
      final m = SettlementViewModel();
      await m.load();
      m.setDeclaredCash('-5');
      expect(m.canSubmit, isFalse);
    });
  });

  group('FuelLoadViewModel', () {
    test('calcula el total y exige litros, precio y kilometraje', () {
      final m = FuelLoadViewModel();
      expect(m.canSubmit, isFalse);
      m.change(liters: '40,5', unitPrice: '1050');
      expect(m.total, 42525);
      expect(m.canSubmit, isFalse, reason: 'falta el kilometraje');
      m.change(odometer: '120350');
      expect(m.canSubmit, isTrue);
      m.change(odometer: '1203,5');
      expect(m.canSubmit, isFalse, reason: 'sin decimales');
    });

    test('registra la carga con el total calculado', () async {
      when(ops.registerFuelLoad(any,
              idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((_) async => const FuelLoadRecord(
              carPatent: 'AB123CD',
              liters: 40,
              totalAmount: 42000,
              odometerKm: 120350,
              anomaly: false));
      final m = FuelLoadViewModel()
        ..change(liters: '40', unitPrice: '1050', odometer: '120350');
      m.setPayment(FuelPayment.card);
      await m.submit();
      final input = verify(ops.registerFuelLoad(captureAny,
              idempotencyKey: anyNamed('idempotencyKey')))
          .captured
          .single as FuelLoadInput;
      expect(input.totalAmount, 42000);
      expect(input.paymentMethod, FuelPayment.card);
      expect(m.result!.carPatent, 'AB123CD');
    });

    test('404 sin vehículo en uso y 400 de kilometraje se muestran', () async {
      when(ops.registerFuelLoad(any,
              idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer(
              (_) async => throw _fail(404, 'No tenés un vehículo en uso'));
      final m = FuelLoadViewModel()
        ..change(liters: '40', unitPrice: '1050', odometer: '10');
      await m.submit();
      expect(m.result, isNull);
      expect(m.failure, isNotNull);

      when(ops.registerFuelLoad(any,
              idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((_) async => throw _fail(
              400, 'El kilometraje es menor que el de la última carga'));
      await m.submit();
      expect(m.failure, contains('kilometraje es menor'));
    });
  });

  group('AccidentViewModel', () {
    test('exige la descripción y manda la ocurrencia y las marcas', () async {
      when(ops.reportAccident(any, idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((_) async => const AccidentRecord(
              vehicleUnusable: true, carPatent: 'AB123CD'));
      final m = AccidentViewModel()..now = () => DateTime.utc(2026, 10, 18, 15);
      expect(m.canSubmit, isFalse);
      m.change(description: 'Choque trasero');
      m.setFlag(vehicleUnusable: true, thirdParties: true);
      await m.submit();
      final input = verify(ops.reportAccident(captureAny,
              idempotencyKey: anyNamed('idempotencyKey')))
          .captured
          .single as AccidentInput;
      expect(input.occurredAt, DateTime.utc(2026, 10, 18, 15));
      expect(input.vehicleUnusable, isTrue);
      expect(input.thirdPartiesInvolved, isTrue);
      expect(input.injuries, isFalse);
      expect(m.result!.vehicleUnusable, isTrue);
    });

    test('guarda assignmentKept y su motivo para mostrarlos', () async {
      when(ops.reportAccident(any, idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((_) async => const AccidentRecord(
              vehicleUnusable: true,
              assignmentKept: true,
              assignmentKeptReason: 'Tenés un pedido en curso'));
      final m = AccidentViewModel()..change(description: 'Choque');
      await m.submit();
      expect(m.result!.assignmentKept, isTrue);
      expect(m.result!.assignmentKeptReason, 'Tenés un pedido en curso');
    });

    test('un error del back se muestra y no hay resultado', () async {
      when(ops.reportAccident(any, idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer(
              (_) async => throw _fail(400, 'La fecha no puede ser futura'));
      final m = AccidentViewModel()..change(description: 'Choque');
      await m.submit();
      expect(m.result, isNull);
      expect(m.failure, contains('no puede ser futura'));
    });
  });

  group('reintentos sin duplicar', () {
    DioException offline() => DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError);

    test('siniestro: el reintento manda la misma hora y la misma clave',
        () async {
      var t = DateTime.utc(2026, 10, 18, 15);
      final keys = <String?>[];
      final inputs = <AccidentInput>[];
      var n = 0;
      when(ops.reportAccident(any, idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((i) async {
        inputs.add(i.positionalArguments[0] as AccidentInput);
        keys.add(i.namedArguments[#idempotencyKey] as String?);
        if (n++ == 0) throw offline();
        return const AccidentRecord(vehicleUnusable: false);
      });
      final m = AccidentViewModel()..now = () => t;
      m.change(description: 'Choque');
      await m.submit();
      expect(m.result, isNull);
      t = t.add(const Duration(minutes: 5));
      await m.submit();
      expect(m.result, isNotNull);
      expect(inputs[1].occurredAt, inputs[0].occurredAt);
      expect(keys[1], keys[0]);
      expect(keys[0], isNotEmpty);
    });

    test('siniestro: si cambia el formulario es otra intención', () async {
      final keys = <String?>[];
      when(ops.reportAccident(any, idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((i) async {
        keys.add(i.namedArguments[#idempotencyKey] as String?);
        throw offline();
      });
      final m = AccidentViewModel()..change(description: 'Choque');
      await m.submit();
      m.change(description: 'Choque trasero');
      await m.submit();
      expect(keys[1], isNot(keys[0]));
    });

    test(
        'combustible: la clave se conserva sin respuesta y se renueva tras '
        'un rechazo', () async {
      final keys = <String?>[];
      var n = 0;
      when(ops.registerFuelLoad(any,
              idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((i) async {
        keys.add(i.namedArguments[#idempotencyKey] as String?);
        n++;
        if (n == 1) throw offline();
        throw _fail(400, 'El kilometraje es menor que el de la última carga');
      });
      final m = FuelLoadViewModel()
        ..change(liters: '40', unitPrice: '1050', odometer: '10');
      await m.submit();
      await m.submit();
      await m.submit();
      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[1]));
    });

    test('rendición: misma clave al reintentar sin respuesta', () async {
      when(ops.mySettlement()).thenAnswer((_) async => _s());
      when(ops.expenseCategories()).thenAnswer((_) async => const []);
      final keys = <String?>[];
      when(ops.submitSettlement('s1',
              declaredCash: anyNamed('declaredCash'),
              expenses: anyNamed('expenses'),
              notes: anyNamed('notes'),
              idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((i) async {
        keys.add(i.namedArguments[#idempotencyKey] as String?);
        throw offline();
      });
      final m = SettlementViewModel();
      await m.load();
      m.setDeclaredCash('100');
      await m.submit();
      await m.submit();
      expect(keys[1], keys[0]);
      m.setDeclaredCash('200');
      await m.submit();
      expect(keys[2], isNot(keys[1]));
    });

    test('rendición: tras un 409 se relee el estado real', () async {
      var calls = 0;
      when(ops.mySettlement()).thenAnswer((_) async =>
          calls++ == 0 ? _s() : _s(status: SettlementStatus.submitted));
      when(ops.expenseCategories()).thenAnswer((_) async => const []);
      when(ops.submitSettlement('s1',
              declaredCash: anyNamed('declaredCash'),
              expenses: anyNamed('expenses'),
              notes: anyNamed('notes'),
              idempotencyKey: anyNamed('idempotencyKey')))
          .thenAnswer((_) async =>
              throw _fail(409, 'La rendición no está abierta para presentar'));
      final m = SettlementViewModel();
      await m.load();
      m.setDeclaredCash('0');
      await m.submit();
      expect(m.submitError, contains('no está abierta'));
      expect(m.settlement!.status, SettlementStatus.submitted);
    });

    group('vista previa de la diferencia', () {
      Settlement open0() => const Settlement(
          id: 's1',
          number: 1,
          businessDate: 'x',
          status: SettlementStatus.open,
          expectedCash: 50000);

      Future<SettlementViewModel> cargada() async {
        when(ops.mySettlement()).thenAnswer((_) async => open0());
        when(ops.expenseCategories()).thenAnswer((_) async =>
            const [ExpenseCategory(id: 'c1', name: 'Combustible')]);
        final m = SettlementViewModel(previewDebounce: Duration.zero);
        await m.load();
        return m;
      }

      Future<void> esperar() async {
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      }

      test('la diferencia es la que devuelve el back, no una cuenta de la app',
          () async {
        when(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async => const SettlementPreview(
                expectedCash: 50000, difference: -123.45));
        final m = await cargada();
        m.setDeclaredCash('46.000');
        m.addExpense();
        m.updateExpense(m.expenses.single, categoryId: 'c1', amount: '3500');
        await esperar();
        expect(m.previewDifference, -123.45);
        final c = verify(ops.previewSettlement('s1',
                declaredCash: captureAnyNamed('declaredCash'),
                expenseAmounts: captureAnyNamed('expenseAmounts')))
            .captured;
        expect(c[c.length - 2], 46000);
        expect(c.last, [3500]);
      });

      test('si la consulta falla no hay diferencia: no se inventa', () async {
        when(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async => throw _fail(500, 'caído'));
        final m = await cargada();
        m.setDeclaredCash('46.000');
        await esperar();
        expect(m.previewDifference, isNull);
      });

      test('sin efectivo legible no consulta y borra la diferencia anterior',
          () async {
        when(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async =>
                const SettlementPreview(expectedCash: 50000, difference: 10));
        final m = await cargada();
        m.setDeclaredCash('50.010');
        await esperar();
        expect(m.previewDifference, 10);
        m.setDeclaredCash('');
        await esperar();
        expect(m.previewDifference, isNull);
        verify(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .called(1);
      });

      test('un gasto a medio tipear no viaja en la consulta', () async {
        when(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async =>
                const SettlementPreview(expectedCash: 50000, difference: 0));
        final m = await cargada();
        m.setDeclaredCash('50.000');
        m.addExpense();
        await esperar();
        final c = verify(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: captureAnyNamed('expenseAmounts')))
            .captured;
        expect(c.last, isEmpty);
      });

      test('una respuesta lenta de un valor viejo no pisa a la del actual',
          () async {
        final lenta = Completer<SettlementPreview>();
        when(ops.previewSettlement('s1',
                declaredCash: 1, expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) => lenta.future);
        when(ops.previewSettlement('s1',
                declaredCash: 2, expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async =>
                const SettlementPreview(expectedCash: 50000, difference: 222));
        final m = await cargada();
        m.setDeclaredCash('1');
        await esperar();
        m.setDeclaredCash('2');
        await esperar();
        expect(m.previewDifference, 222);
        lenta.complete(
            const SettlementPreview(expectedCash: 49000, difference: 111));
        await esperar();
        expect(m.previewDifference, 222, reason: 'la vieja llegó tarde');
        expect(m.expectedCash, 50000);
      });

      test('el esperado que se muestra es el de la vista previa', () async {
        when(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async =>
                const SettlementPreview(expectedCash: 51234, difference: 5));
        final m = await cargada();
        expect(m.expectedCash, 50000, reason: 'sin preview, el de la lectura');
        m.setDeclaredCash('50.000');
        await esperar();
        expect(m.expectedCash, 51234);
        m.setDeclaredCash('50.001');
        expect(m.expectedCash, 51234, reason: 'no vuelve al viejo al teclear');
      });

      test('al releer la rendición se vuelve a pedir la diferencia', () async {
        var esperado = 50000;
        when(ops.mySettlement()).thenAnswer((_) async => Settlement(
            id: 's1',
            number: 1,
            businessDate: 'x',
            status: SettlementStatus.open,
            expectedCash: esperado));
        when(ops.expenseCategories()).thenAnswer((_) async => const []);
        when(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async => SettlementPreview(
                expectedCash: esperado, difference: 50000 - esperado));
        final m = SettlementViewModel(previewDebounce: Duration.zero);
        await m.load();
        m.setDeclaredCash('50.000');
        await esperar();
        expect(m.previewDifference, 0);
        esperado = 52000;
        await m.load();
        await esperar();
        expect(m.expectedCash, 52000);
        expect(m.previewDifference, -2000);
      });

      test('un gasto con importe ilegible: sin diferencia y con aviso',
          () async {
        when(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async =>
                const SettlementPreview(expectedCash: 50000, difference: 0));
        final m = await cargada();
        m.setDeclaredCash('50.000');
        m.addExpense();
        m.updateExpense(m.expenses.single, categoryId: 'c1', amount: '12abc');
        await esperar();
        expect(m.previewDifference, isNull);
        expect(m.previewHint, contains('Revisá el importe del gasto'));
        verifyNever(ops.previewSettlement('s1',
            declaredCash: anyNamed('declaredCash'),
            expenseAmounts: anyNamed('expenseAmounts')));
        m.updateExpense(m.expenses.single, amount: '3500');
        await esperar();
        expect(m.previewHint, isNull);
        expect(m.previewDifference, 0);
      });

      test('mientras teclea espera: una sola consulta con el último valor',
          () async {
        when(ops.previewSettlement('s1',
                declaredCash: anyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .thenAnswer((_) async =>
                const SettlementPreview(expectedCash: 50000, difference: 7));
        when(ops.mySettlement()).thenAnswer((_) async => open0());
        when(ops.expenseCategories()).thenAnswer((_) async => const []);
        final m = SettlementViewModel(
            previewDebounce: const Duration(milliseconds: 30));
        await m.load();
        m.setDeclaredCash('5');
        m.setDeclaredCash('50');
        m.setDeclaredCash('500');
        expect(m.previewDifference, isNull);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(m.previewDifference, 7);
        final c = verify(ops.previewSettlement('s1',
                declaredCash: captureAnyNamed('declaredCash'),
                expenseAmounts: anyNamed('expenseAmounts')))
            .captured;
        expect(c, [500]);
      });
    });
  });
}
