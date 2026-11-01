import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/ui/views/accident/accident_view.dart';
import 'package:splg_driver/ui/views/settlement/settlement_view.dart';
import 'package:splg_driver/ui/views/workday/workday_view.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

Widget app(Widget home) => MaterialApp(theme: AppTheme.lightTheme, home: home);

Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  late MockDriverOpsRepository ops;

  setUp(() {
    registerServices();
    ops = locator<DriverOpsRepository>() as MockDriverOpsRepository;
  });
  tearDown(() => locator.reset());

  testWidgets('Mi jornada: iniciar y luego finalizar (con confirmación)',
      (t) async {
    final n = DateTime.now();
    final inAt = DateTime(n.year, n.month, n.day, 0, 1);
    Workday? current;
    when(ops.workday).thenAnswer((_) => current);
    when(ops.currentWorkday()).thenAnswer((_) async => current);
    when(ops.checkIn()).thenAnswer((_) async =>
        current = Workday(id: 'a', workDate: apiDay(n), checkInAt: inAt));
    when(ops.checkOut()).thenAnswer((_) async => current = Workday(
        id: 'a',
        workDate: apiDay(n),
        checkInAt: inAt,
        checkOutAt: inAt.add(const Duration(hours: 8)),
        durationMinutes: 480));
    await t.pumpWidget(app(const WorkdayView()));
    await settle(t);
    expect(find.text('Todavía no iniciaste'), findsOneWidget);
    expect(find.byKey(const Key('workday-finish')), findsNothing);

    await t.tap(find.byKey(const Key('workday-start')));
    await settle(t);
    expect(find.text('Jornada iniciada'), findsOneWidget);
    expect(find.textContaining('Empezaste hoy a las 00:01'), findsOneWidget);

    await t.tap(find.byKey(const Key('workday-finish')));
    await settle(t);
    expect(find.text('Jornada finalizada'), findsOneWidget);
    expect(find.textContaining('8 h 0 min'), findsOneWidget);

    await t.tap(find.byKey(const Key('workday-start')));
    await settle(t);
    expect(find.text('¿Iniciar otra jornada?'), findsOneWidget);
    verify(ops.checkIn()).called(1);
    await t.tap(find.text('Cancelar'));
    await settle(t);
    verifyNever(ops.checkIn());
  });

  testWidgets('Mi jornada: abierta de un día anterior, sin botones', (t) async {
    final old = Workday(
        id: 'a', workDate: '2020-01-02', checkInAt: DateTime(2020, 1, 2, 8));
    when(ops.workday).thenReturn(old);
    when(ops.currentWorkday()).thenAnswer((_) async => old);
    await t.pumpWidget(app(const WorkdayView()));
    await settle(t);
    expect(
        find.textContaining(
            'Tu jornada del 02/01/2020 quedó sin cerrar: corregila desde el panel'),
        findsOneWidget);
    expect(find.byKey(const Key('workday-start')), findsNothing);
    expect(find.byKey(const Key('workday-finish')), findsNothing);
  });

  testWidgets('Mi rendición: declara el efectivo y la presenta', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    when(ops.mySettlement()).thenAnswer((_) async => const Settlement(
            id: 's1',
            number: 4,
            businessDate: '2026-10-18',
            status: SettlementStatus.open,
            expectedCash: 50000,
            orders: [
              SettlementOrder(
                  orderId: 'o1',
                  amountToCollect: 12000,
                  paymentStatus: 'paid',
                  customerName: 'Ana Gómez',
                  deliveryAddress: 'Mitre 1200, Posadas'),
              SettlementOrder(
                  orderId: 'o2abcdefgh',
                  amountToCollect: 5000,
                  paymentStatus: 'paid'),
            ]));
    when(ops.expenseCategories()).thenAnswer((_) async => const []);
    when(ops.submitSettlement('s1',
            declaredCash: anyNamed('declaredCash'),
            expenses: anyNamed('expenses'),
            notes: anyNamed('notes'),
            idempotencyKey: anyNamed('idempotencyKey')))
        .thenAnswer((_) async => const Settlement(
            id: 's1',
            number: 4,
            businessDate: '2026-10-18',
            status: SettlementStatus.submitted,
            expectedCash: 50000,
            declaredCash: 49000,
            difference: -1000));
    when(ops.previewSettlement('s1',
            declaredCash: anyNamed('declaredCash'),
            expenseAmounts: anyNamed('expenseAmounts')))
        .thenAnswer((_) async =>
            const SettlementPreview(expectedCash: 50000, difference: -1000));
    await t.pumpWidget(app(const SettlementView()));
    await settle(t);
    expect(find.byKey(const Key('settlement-expected')), findsOneWidget);
    expect(find.text('\$50.000'), findsOneWidget);
    expect(find.text('Ana Gómez'), findsOneWidget);
    expect(find.text('Mitre 1200, Posadas'), findsOneWidget);
    expect(find.text('Pedido o2abcdef'), findsOneWidget);
    expect(
        t
            .widget<SplgButton>(find.byKey(const Key('settlement-submit')))
            .onPressed,
        isNull);

    await t.enterText(
        find.descendant(
            of: find.byKey(const Key('settlement-cash')),
            matching: find.byType(TextField)),
        '49000');
    await t.pump();
    expect(find.text('Te faltarían'), findsNothing,
        reason:
            'la diferencia la manda el back, tras esperar a que deje de teclear');
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(find.text('Te faltarían'), findsOneWidget);
    await t.tap(find.byKey(const Key('settlement-submit')));
    await settle(t);
    expect(find.byKey(const Key('settlement-state')), findsOneWidget);
    expect(find.text('Faltante'), findsOneWidget);
    expect(find.byKey(const Key('settlement-submit')), findsNothing);
  });

  testWidgets('Mi rendición: si la vista previa falla no se muestra diferencia',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    when(ops.mySettlement()).thenAnswer((_) async => const Settlement(
        id: 's1',
        number: 4,
        businessDate: '2026-10-18',
        status: SettlementStatus.open,
        expectedCash: 50000));
    when(ops.expenseCategories()).thenAnswer((_) async => const []);
    when(ops.previewSettlement('s1',
            declaredCash: anyNamed('declaredCash'),
            expenseAmounts: anyNamed('expenseAmounts')))
        .thenAnswer((_) async => throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionError));
    await t.pumpWidget(app(const SettlementView()));
    await settle(t);
    await t.enterText(
        find.descendant(
            of: find.byKey(const Key('settlement-cash')),
            matching: find.byType(TextField)),
        '49000');
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(find.text('Te faltarían'), findsNothing);
    expect(find.text('Te sobrarían'), findsNothing);
    expect(find.text('Cierra justo'), findsNothing);
  });

  testWidgets('Siniestro: si se mantiene la asignación se muestra el motivo',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    when(ops.reportAccident(any, idempotencyKey: anyNamed('idempotencyKey')))
        .thenAnswer((_) async => const AccidentRecord(
            vehicleUnusable: true,
            assignmentKept: true,
            assignmentKeptReason: 'Tenés un pedido en curso'));
    await t.pumpWidget(app(const AccidentView()));
    await settle(t);
    expect(
        t
            .widget<SplgButton>(find.byKey(const Key('accident-submit')))
            .onPressed,
        isNull);
    await t.enterText(
        find.descendant(
            of: find.byKey(const Key('accident-description')),
            matching: find.byType(TextField)),
        'Choque trasero');
    await t.pump();
    await t.tap(find.byKey(const Key('accident-submit')));
    await settle(t);
    expect(find.byKey(const Key('accident-kept')), findsOneWidget);
    expect(find.textContaining('Tu vehículo quedó fuera de servicio'),
        findsWidgets);
    expect(
        find.textContaining('Avisamos a los administradores'), findsOneWidget);
  });
}
