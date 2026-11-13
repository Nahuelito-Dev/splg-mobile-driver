import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/services/route_batch_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/dialogs/route_batch_offer/route_batch_offer_dialog.dart';
import 'package:splg_driver/ui/views/delivery/delivery_view.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../f35_e4/support.dart' as entrega;
import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

/// Parada con otra fecha o franja que la de `stopJson`.
Map<String, dynamic> stopOn(
  String orderId,
  int sequence, {
  String? date = '2026-11-13',
  (String, String)? slot = ('08:00:00', '12:00:00'),
}) =>
    {
      ...stopJson(orderId, sequence),
      'scheduledDate': date,
      'slot': slot == null
          ? null
          : {'name': 'Mañana', 'startTime': slot.$1, 'endTime': slot.$2},
    };

RouteBatch assigned(List<Map<String, dynamic>> stops) => RouteBatch.fromJson(
    batchJson(status: 'assigned', offerStatus: 'accepted', stops: stops));

void main() {
  group('Fecha del recorrido', () {
    test('día corto en castellano y la franja: «vie 13/11, 08:00–12:00»', () {
      final b = batch(stops: [stopOn('o1', 1), stopOn('o2', 2)]);
      expect(b.scheduleText, 'vie 13/11, 08:00–12:00');
    });

    test(
        'con franjas distintas va de la que abre primero a la que cierra '
        'última; las paradas que salieron no cuentan', () {
      final b = batch(stops: [
        stopOn('o1', 1, slot: ('10:00:00', '13:00:00')),
        stopOn('o2', 2, slot: ('08:00:00', '12:00:00')),
        {
          ...stopOn('o3', 3, slot: ('18:00:00', '21:00:00')),
          'active': false,
        },
      ]);
      expect(b.scheduleText, 'vie 13/11, 08:00–13:00');
    });

    test('sin franja: sólo el día; sin fecha: nada', () {
      expect(batch(stops: [stopOn('o1', 1, slot: null)]).scheduleText,
          'vie 13/11');
      expect(batch(stops: [stopOn('o1', 1, date: '')]).scheduleText, isNull);
    });

    test('de un día al otro usa fecha y hora reales, no mezcla las horas', () {
      // vie 22:00–23:00 y sáb 01:00–03:00: comparar sólo horas daba
      // «01:00–23:00».
      final b = batch(stops: [
        stopOn('o1', 1, slot: ('22:00:00', '23:00:00')),
        stopOn('o2', 2, date: '2026-11-14', slot: ('01:00:00', '03:00:00')),
      ]);
      expect(b.scheduleText, 'vie 13/11 22:00 a sáb 14/11 03:00');
    });

    test(
        'supuesto: en SPLG una franja no cruza la medianoche (el back exige '
        'inicio < fin); si llegara una, el fin es del día siguiente', () {
      final b = batch(stops: [
        stopOn('o1', 1, slot: ('22:00:00', '02:00:00')),
        stopOn('o2', 2, date: '2026-11-14', slot: ('01:00:00', '03:00:00')),
      ]);
      expect(b.scheduleText, 'vie 13/11 22:00 a sáb 14/11 03:00');
      expect(
          batch(stops: [stopOn('o1', 1, slot: ('22:00:00', '02:00:00'))])
              .scheduleText,
          'vie 13/11 22:00 a sáb 14/11 02:00');
    });

    test('paradas de dos días los nombra a los dos, en orden', () {
      final b = batch(stops: [
        stopOn('o1', 1, date: '2026-11-14', slot: null),
        stopOn('o2', 2, slot: null),
      ]);
      expect(b.scheduleText, 'vie 13/11 y sáb 14/11');
    });

    testWidgets('la oferta muestra la fecha', (t) async {
      registerServices();
      addTearDown(locator.reset);
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: RouteBatchOfferDialog(
            request: DialogRequest(
                data: batch(stops: [stopOn('o1', 1), stopOn('o2', 2)])),
            completer: (_) {}),
      ));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('batch-schedule'))).data,
          'vie 13/11, 08:00–12:00');
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Paradas del recorrido aceptado', () {
    late MockTripService trips;
    late MockRouteBatchRepository batches;

    setUp(() {
      registerServices();
      trips = locator<TripService>() as MockTripService;
      batches = locator<RouteBatchRepository>() as MockRouteBatchRepository;
      when(trips.order('o1'))
          .thenAnswer((_) async => entrega.tripWithEmpties(status: 'accepted'));
      when(trips.customerRating(any)).thenAnswer(
          (_) async => const RatingSummary(average: 4.5, count: 12));
      DeliveryView.debugMapBuilder = (_, __) => const SizedBox.expand();
      DeliveryView.debugViewModelFactory = (id) => DeliveryViewModel(
          orderId: id,
          trips: trips,
          batches: batches,
          pollInterval: const Duration(hours: 1));
    });
    tearDown(() {
      DeliveryView.debugMapBuilder = null;
      DeliveryView.debugViewModelFactory = null;
      locator.reset();
    });

    Future<void> pump(WidgetTester t) async {
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const DeliveryView(orderId: 'o1'),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }

    test('el ViewModel ubica el pedido en el recorrido asignado', () async {
      when(batches.mine()).thenAnswer((_) async => [
            assigned([stopOn('o0', 1), stopOn('o1', 2), stopOn('o3', 3)]),
          ]);
      final model = DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          batches: batches,
          pollInterval: const Duration(hours: 1));
      await model.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(model.batchText, 'Recorrido: parada 2 de 3');
      expect([for (final s in model.batchStops) s.orderId], ['o0', 'o1', 'o3']);
      model.dispose();
    });

    test(
        'un recorrido que todavía se ofrece o que no tiene el pedido no '
        'cuenta', () async {
      when(batches.mine()).thenAnswer((_) async => [
            batch(stops: [stopOn('o1', 1)]),
            assigned([stopOn('o7', 1), stopOn('o8', 2)]),
          ]);
      final model = DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          batches: batches,
          pollInterval: const Duration(hours: 1));
      await model.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(model.routeBatch, isNull);
      expect(model.batchText, isNull);
      model.dispose();
    });

    testWidgets(
        'después de aceptar se ven las paradas en orden, con la '
        'actual marcada', (t) async {
      when(batches.mine()).thenAnswer((_) async => [
            assigned([stopOn('o3', 3), stopOn('o0', 1), stopOn('o1', 2)]),
          ]);
      await pump(t);
      expect(t.widget<Text>(find.byKey(const Key('trip-batch-text'))).data,
          'Recorrido: parada 2 de 3');

      await t.tap(find.byKey(const Key('trip-batch')));
      await t.pumpAndSettle();
      final list = find.byKey(const Key('trip-batch-stops'));
      expect(list, findsOneWidget);
      expect(find.text('vie 13/11, 08:00–12:00'), findsOneWidget);
      final tops = [
        for (final n in [1, 2, 3])
          t
              .getTopLeft(find.descendant(
                  of: list, matching: find.byKey(Key('batch-stop-$n'))))
              .dy
      ];
      expect(tops[0], lessThan(tops[1]));
      expect(tops[1], lessThan(tops[2]));
      expect(
          find.descendant(
              of: find.byKey(const Key('batch-stop-2')),
              matching: find.byKey(const Key('batch-stop-current'))),
          findsOneWidget);
      expect(find.byKey(const Key('batch-stop-current')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    Future<void> openStops(WidgetTester t) async {
      await t.tap(find.byKey(const Key('trip-batch')));
      await t.pumpAndSettle();
    }

    Finder inTile(int n, Finder f) =>
        find.descendant(of: find.byKey(Key('batch-stop-$n')), matching: f);

    testWidgets(
        'si una parada sale del lote, la fila y las tarjetas usan la '
        'misma numeración (1..M)', (t) async {
      // La 1 original se canceló; el chofer va por la 3 original.
      when(trips.order('o3'))
          .thenAnswer((_) async => entrega.tripWithEmpties(status: 'accepted'));
      DeliveryView.debugViewModelFactory = (_) => DeliveryViewModel(
          orderId: 'o3',
          trips: trips,
          batches: batches,
          pollInterval: const Duration(hours: 1));
      when(batches.mine()).thenAnswer((_) async => [
            assigned([
              {...stopOn('o0', 1), 'active': false},
              stopOn('o2', 2),
              stopOn('o3', 3),
            ]),
          ]);
      await pump(t);
      expect(t.widget<Text>(find.byKey(const Key('trip-batch-text'))).data,
          'Recorrido: parada 2 de 2');
      await openStops(t);
      expect(find.byKey(const Key('batch-stop-3')), findsNothing);
      expect(inTile(2, find.byKey(const Key('batch-stop-current'))),
          findsOneWidget);
      expect(inTile(2, find.text('2')), findsOneWidget);
      expect(inTile(1, find.text('1')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
        'las paradas entregadas quedan como hechas sin perder su '
        'número', (t) async {
      when(batches.mine()).thenAnswer((_) async => [
            assigned([
              {...stopOn('o0', 1), 'orderStatus': 'delivered'},
              stopOn('o1', 2),
              stopOn('o3', 3),
            ]),
          ]);
      await pump(t);
      expect(t.widget<Text>(find.byKey(const Key('trip-batch-text'))).data,
          'Recorrido: parada 2 de 3');
      await openStops(t);
      expect(inTile(1, find.byKey(const Key('batch-stop-done-1'))),
          findsOneWidget);
      expect(inTile(1, find.text('Parada 1 · Entregada')), findsOneWidget);
      // Las que faltan siguen con su número y sin marca de hecha.
      expect(find.byKey(const Key('batch-stop-done-2')), findsNothing);
      expect(find.byKey(const Key('batch-stop-done-3')), findsNothing);
      expect(inTile(3, find.text('3')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('un pedido suelto no muestra recorrido', (t) async {
      when(batches.mine()).thenAnswer((_) async => []);
      await pump(t);
      expect(find.byKey(const Key('trip-batch')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });
}
