import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/delivery/delivery_view.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

/// Pedido en curso con la sección «Vacías» (393x852, 1x). El mapa va como
/// placeholder.
Future<void> pump(WidgetTester t, {Size size = const Size(393, 852)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    home: const DeliveryView(orderId: 'o1'),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  late MockTripService trips;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    when(trips.order('o1')).thenAnswer((_) async => tripWithEmpties());
    when(trips.customerRating('c1'))
        .thenAnswer((_) async => const RatingSummary(average: 4.5, count: 12));
    DeliveryView.debugMapBuilder = (_, __) => Container(
        color: const Color(0xFFE8E6E1),
        child: const Center(child: Text('mapa')));
    DeliveryView.debugViewModelFactory = (id) => DeliveryViewModel(
        orderId: id, trips: trips, pollInterval: const Duration(hours: 1));
  });
  tearDown(() {
    DeliveryView.debugMapBuilder = null;
    DeliveryView.debugViewModelFactory = null;
    locator.reset();
  });

  testGoldens('en camino: sección «Vacías» antes del QR', (t) async {
    await loadAppFonts();
    await pump(t);
    // El chofer recibió una vacía menos de 10 kg.
    await t.tap(find.byKey(const Key('empties-remove-$k10')));
    await t.pump();
    expect(find.text('Vacías'), findsOneWidget);
    expect(find.text('Esperadas: 2'), findsNWidgets(2));
    expect(find.byKey(const Key('empties-value-$k10')), findsOneWidget);
    expect(find.text('El cliente compró 1 envase: no devuelve vacía por ese.'),
        findsOneWidget);
    expect(find.text('Llegué / Entregar'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/delivery_empties.png'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('el stepper respeta 0..esperadas', (t) async {
    await pump(t);
    final add = find.byKey(const Key('empties-add-$k10'));
    final remove = find.byKey(const Key('empties-remove-$k10'));
    final value = find.byKey(const Key('empties-value-$k10'));
    expect(t.widget<IconButton>(add).onPressed, isNull);
    expect((t.widget<Text>(value)).data, '2');
    await t.tap(remove);
    await t.tap(remove);
    await t.pump();
    expect((t.widget<Text>(value)).data, '0');
    expect(t.widget<IconButton>(remove).onPressed, isNull);
    expect(t.widget<IconButton>(add).onPressed, isNotNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('aceptado: todavía no aparece la sección', (t) async {
    when(trips.order('o1'))
        .thenAnswer((_) async => tripWithEmpties(status: 'accepted'));
    await pump(t);
    expect(find.byKey(const Key('empties-card')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('en pantalla chica no desborda', (t) async {
    await pump(t, size: const Size(320, 568));
    expect(find.byKey(const Key('empties-card')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
