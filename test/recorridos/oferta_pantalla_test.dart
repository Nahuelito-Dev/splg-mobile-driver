import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/services/route_batch_repository.dart';
import 'package:splg_driver/ui/dialogs/route_batch_offer/route_batch_offer_dialog.dart';
import 'package:splg_driver/ui/dialogs/route_batch_offer/route_batch_offer_dialog_model.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

void main() {
  late MockRouteBatchRepository repo;
  late List<DialogResponse> responses;

  setUp(() {
    registerServices();
    repo = locator<RouteBatchRepository>() as MockRouteBatchRepository;
    responses = [];
  });
  tearDown(() => locator.reset());

  Future<void> pump(WidgetTester t, RouteBatch b) async {
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: RouteBatchOfferDialog(
          request: DialogRequest(data: b), completer: responses.add),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }

  RouteBatch tres() => batch(ttl: const Duration(seconds: 45), stops: [
        stopJson('o1', 1),
        stopJson('o2', 2, leg: 2.4),
        stopJson('o3', 3, leg: 0.8),
        stopJson('o4', 4, active: false),
      ]);

  testGoldens('muestra las paradas activas en orden, el peso y la cuenta',
      (t) async {
    await loadAppFonts();
    await pump(t, tres());
    expect(find.text('Recorrido ofrecido'), findsOneWidget);
    expect(find.text('3 paradas'), findsOneWidget);
    expect(find.text('75,5 kg - 3,2 km'), findsOneWidget);
    expect(find.byKey(const Key('batch-stop-1')), findsOneWidget);
    expect(find.byKey(const Key('batch-stop-3')), findsOneWidget);
    expect(find.byKey(const Key('batch-stop-4')), findsNothing);
    expect(find.text('Aceptar recorrido'), findsOneWidget);
    expect(find.textContaining('La oferta vence en'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/route_batch_offer.png'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Aceptar recorrido manda el POST y confirma', (t) async {
    when(repo.accept('b1')).thenAnswer((_) async => const RouteBatchDecision(
        batchId: 'b1', accepted: true, assignedOrders: 2));
    await pump(t, tres());
    await t.tap(find.byKey(const Key('batch-accept')));
    await t.pump();
    await t.pump();
    verify(repo.accept('b1')).called(1);
    expect(responses.single.confirmed, true);
    expect((responses.single.data as Map)['outcome'], BatchOutcome.accepted);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Rechazar cierra sin tocar el back', (t) async {
    await pump(t, tres());
    await t.tap(find.byKey(const Key('batch-reject')));
    await t.pump();
    verifyNever(repo.accept(any));
    expect(responses.single.confirmed, false);
    expect((responses.single.data as Map)['outcome'], BatchOutcome.rejected);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('un rechazo del back (409) vuelve con el texto', (t) async {
    when(repo.accept('b1'))
        .thenThrow(http(409, {'message': 'La oferta del lote venció'}));
    await pump(t, tres());
    await t.tap(find.byKey(const Key('batch-accept')));
    await t.pump();
    await t.pump();
    expect((responses.single.data as Map)['outcome'], BatchOutcome.refused);
    expect(
        (responses.single.data as Map)['error'], 'La oferta del lote venció');
    await t.pumpWidget(const SizedBox());
  });
}
