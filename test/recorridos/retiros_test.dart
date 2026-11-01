import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/recovery_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/common/pickups_model.dart';
import 'package:splg_driver/ui/views/completed/completed_view.dart';
import 'package:splg_driver/ui/views/completed/completed_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery/delivery_view.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';
import 'support.dart';

Future<void> pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(393, 852);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    home: home,
  ));
  await t.pump();
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  late MockRecoveryRepository repo;
  late MockTripService trips;

  setUp(() {
    registerServices();
    repo = locator<RecoveryRepository>() as MockRecoveryRepository;
    trips = locator<TripService>() as MockTripService;
    when(trips.order('o1')).thenAnswer((_) async => trip());
    when(trips.customerRating('c1')).thenAnswer((_) async => null);
    DeliveryView.debugMapBuilder = (_, __) => Container(
        color: const Color(0xFFE8E6E1),
        child: const Center(child: Text('mapa')));
    DeliveryView.debugViewModelFactory = (id) => DeliveryViewModel(
        orderId: id,
        trips: trips,
        recovery: repo,
        pollInterval: const Duration(hours: 1));
    CompletedView.debugViewModelFactory = (id) => CompletedViewModel(
        orderId: id, trips: trips, recovery: repo, goHome: () {});
  });
  tearDown(() {
    DeliveryView.debugMapBuilder = null;
    DeliveryView.debugViewModelFactory = null;
    CompletedView.debugViewModelFactory = null;
    NavigationLauncher.launcher = null;
    locator.reset();
  });

  group('PickupsModel', () {
    test('se queda con los retiros de este pedido', () async {
      when(repo.pickups()).thenAnswer((_) async => [
            pickup(),
            pickup(noticeId: 'n2', orderId: 'otro'),
          ]);
      final m = PickupsModel(orderId: 'o1', repo: repo);
      await m.load();
      expect(m.pickups.map((p) => p.noticeId), ['n1']);
      m.dispose();
    });

    test('con el módulo apagado o un fallo de lectura no hay nada ni error',
        () async {
      when(repo.pickups()).thenAnswer((_) async => []);
      final m = PickupsModel(orderId: 'o1', repo: repo);
      await m.load();
      expect(m.pickups, isEmpty);
      when(repo.pickups()).thenThrow(http(500));
      await m.load();
      expect(m.pickups, isEmpty);
      expect(m.error, isNull);
      m.dispose();
    });

    test('load con `every` no relee antes de tiempo', () async {
      when(repo.pickups()).thenAnswer((_) async => []);
      final m = PickupsModel(orderId: 'o1', repo: repo);
      await m.load(every: const Duration(seconds: 30));
      await m.load(every: const Duration(seconds: 30));
      verify(repo.pickups()).called(1);
      m.dispose();
    });

    test('confirmar manda el POST y deja el retiro como hecho', () async {
      when(repo.pickups()).thenAnswer((_) async => [pickup()]);
      final m = PickupsModel(orderId: 'o1', repo: repo);
      await m.load();
      expect(await m.confirm(m.pickups.single), true);
      verify(repo.confirm('n1')).called(1);
      expect(m.isDone('n1'), true);
      // El back todavía lo lista: no se duplica ni se pierde.
      await m.load();
      expect(m.pickups, hasLength(1));
      m.dispose();
    });

    test('un 403 fuera del plazo se muestra y el retiro queda pendiente',
        () async {
      when(repo.pickups()).thenAnswer((_) async => [pickup()]);
      when(repo.confirm('n1')).thenThrow(http(403, {
        'message':
            'El pedido del retiro no está aceptado, en camino ni entregado hace menos de 24 horas'
      }));
      final m = PickupsModel(orderId: 'o1', repo: repo);
      await m.load();
      expect(await m.confirm(m.pickups.single), false);
      expect(m.error, contains('24 horas'));
      expect(m.isDone('n1'), false);
      expect(m.hasBusy, false);
      m.dispose();
    });

    test('"No pude retirarlo" exige motivo y manda el POST con el motivo',
        () async {
      when(repo.pickups()).thenAnswer((_) async => [pickup()]);
      final m = PickupsModel(orderId: 'o1', repo: repo);
      await m.load();
      final p = m.pickups.single;
      expect(await m.notCollected(p, '   '), false);
      expect(m.error, 'Contanos por qué no pudiste retirarlo.');
      expect(await m.notCollected(p, 'x' * 501), false);
      verifyNever(repo.notCollected(any, reason: anyNamed('reason')));
      expect(await m.notCollected(p, 'No estaba'), true);
      verify(repo.notCollected('n1', reason: 'No estaba')).called(1);
      expect(m.pickups, isEmpty);
      m.dispose();
    });

    test('un segundo toque con la respuesta en vuelo no repite el POST',
        () async {
      when(repo.pickups()).thenAnswer((_) async => [pickup()]);
      final m = PickupsModel(orderId: 'o1', repo: repo);
      await m.load();
      final p = m.pickups.single;
      final a = m.confirm(p);
      expect(m.isBusy('n1'), true);
      expect(await m.confirm(p), false);
      await a;
      verify(repo.confirm('n1')).called(1);
      m.dispose();
    });
  });

  group('viaje del pedido', () {
    testGoldens('muestra "Retirar envase" con las dos acciones', (t) async {
      await loadAppFonts();
      when(repo.pickups()).thenAnswer((_) async => [pickup()]);
      await pump(t, const DeliveryView(orderId: 'o1'));
      expect(find.text('Retirar envase SPLG-00042'), findsOneWidget);
      expect(find.byKey(const Key('pickup-confirm')), findsOneWidget);
      expect(find.byKey(const Key('pickup-not-collected')), findsOneWidget);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/trip_pickup.png'));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('sin retiros (módulo apagado) no aparece nada', (t) async {
      when(repo.pickups()).thenAnswer((_) async => []);
      await pump(t, const DeliveryView(orderId: 'o1'));
      expect(find.byKey(const Key('pickup-card')), findsNothing);
      expect(find.textContaining('Retirar envase'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('"Retiré el envase" confirma en el back', (t) async {
      when(repo.pickups()).thenAnswer((_) async => [pickup()]);
      await pump(t, const DeliveryView(orderId: 'o1'));
      await t.ensureVisible(find.byKey(const Key('pickup-confirm')));
      await t.tap(find.byKey(const Key('pickup-confirm')));
      await t.pump();
      await t.pump();
      verify(repo.confirm('n1')).called(1);
      expect(find.text('Envase SPLG-00042 retirado'), findsOneWidget);
      expect(find.byKey(const Key('pickup-confirm')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('"No pude retirarlo" pide el motivo y lo manda', (t) async {
      when(repo.pickups()).thenAnswer((_) async => [pickup()]);
      await pump(t, const DeliveryView(orderId: 'o1'));
      await t.ensureVisible(find.byKey(const Key('pickup-not-collected')));
      await t.tap(find.byKey(const Key('pickup-not-collected')));
      await t.pumpAndSettle();
      // Sin motivo no se puede enviar.
      expect(
          t
              .widget<SplgButton>(find.byKey(const Key('pickup-reason-send')))
              .onPressed,
          isNull);
      await t.enterText(find.byKey(const Key('pickup-reason')), 'No estaba');
      await t.pump();
      await t.tap(find.byKey(const Key('pickup-reason-send')));
      await t.pumpAndSettle();
      verify(repo.notCollected('n1', reason: 'No estaba')).called(1);
      expect(find.byKey(const Key('pickup-card')), findsNothing);
      expect(find.text('Retirar envase SPLG-00042'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('un rechazo del back se muestra en la tarjeta', (t) async {
      when(repo.pickups()).thenAnswer((_) async => [pickup()]);
      when(repo.confirm('n1'))
          .thenThrow(http(409, {'message': 'El caso ya cerró'}));
      await pump(t, const DeliveryView(orderId: 'o1'));
      await t.ensureVisible(find.byKey(const Key('pickup-confirm')));
      await t.tap(find.byKey(const Key('pickup-confirm')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('pickup-error')), findsOneWidget);
      expect(find.text('El caso ya cerró'), findsOneWidget);
      expect(find.byKey(const Key('pickup-confirm')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('pedido completado', () {
    testWidgets('con el pedido entregado muestra el retiro y el plazo de 24 h',
        (t) async {
      when(repo.pickups())
          .thenAnswer((_) async => [pickup(orderStatus: 'delivered')]);
      await pump(t, const CompletedView(orderId: 'o1'));
      expect(find.text('Retirar envase SPLG-00042'), findsOneWidget);
      expect(find.byKey(const Key('pickup-window')), findsOneWidget);
      await t.tap(find.byKey(const Key('pickup-confirm')));
      await t.pump();
      await t.pump();
      verify(repo.confirm('n1')).called(1);
      await t.pumpWidget(const SizedBox());
    });
  });
}
