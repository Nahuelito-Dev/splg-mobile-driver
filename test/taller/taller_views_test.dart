import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_repository.dart';
import 'package:splg_driver/ui/dialogs/maintenance_proposal/maintenance_proposal_dialog.dart';
import 'package:splg_driver/ui/dialogs/maintenance_proposal/route_notice_presenter.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'package:splg_driver/ui/views/taller/taller_view.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'maintenance_logic_test.dart' as logic;

Widget app(Widget home) => MaterialApp(
    debugShowCheckedModeBanner: false, theme: AppTheme.lightTheme, home: home);

Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> phone(WidgetTester t) async {
  t.view.physicalSize = const Size(393, 852);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

/// Vence mañana respecto del reloj real, para que la cuenta regresiva viva.
Map<String, dynamic> live(
    {String id = 'p1', Map<String, dynamic> extra = const {}}) {
  final now = DateTime.now().toUtc();
  return logic.json(
    id: id,
    start: now.add(const Duration(days: 3)).toIso8601String(),
    end: now.add(const Duration(days: 3, hours: 4)).toIso8601String(),
    expires: now.add(const Duration(hours: 5, minutes: 30)).toIso8601String(),
    extra: extra,
  );
}

void main() {
  late MockMaintenanceRepository repo;

  setUp(() {
    registerServices();
    repo = locator<MaintenanceRepository>() as MockMaintenanceRepository;
    locator.unregister<MaintenanceBoard>();
    locator.registerSingleton<MaintenanceBoard>(MaintenanceBoard());
    when(repo.settings()).thenAnswer((_) async => logic.settings);
  });
  tearDown(() => locator.reset());

  void serve(List<Map<String, dynamic>> items) =>
      when(repo.proposals()).thenAnswer((_) async => MaintenancePage(
          proposals: [for (final j in items) MaintenanceProposal.fromJson(j)],
          total: items.length));

  testWidgets('Taller: la propuesta vigente con su cuenta regresiva',
      (t) async {
    serve([
      live(extra: {'urgent': true})
    ]);
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    expect(find.text('AB123CD · Service: aceite y filtros'), findsOneWidget);
    expect(find.text('Urgente'), findsOneWidget);
    expect(find.textContaining('vence en 5 h 29 min'), findsOneWidget);
    expect(find.byKey(const Key('taller-accept-p1')), findsOneWidget);
    expect(find.byKey(const Key('taller-reject-p1')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Taller: sin turnos muestra el estado vacío', (t) async {
    serve([]);
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    expect(find.text('Sin turnos de taller'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Taller: error de lectura con Reintentar', (t) async {
    when(repo.proposals()).thenThrow(logic.fail(500, 'caído'));
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    expect(find.text('Reintentar'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Taller: aceptar pasa a "Esperando al administrador"', (t) async {
    serve([live()]);
    when(repo.accept('p1')).thenAnswer((_) async {
      serve([
        live(extra: {'status': 'accepted'})
      ]);
      return MaintenanceProposal.fromJson(live(extra: {'status': 'accepted'}));
    });
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    await t.tap(find.byKey(const Key('taller-accept-p1')));
    await settle(t);
    verify(repo.accept('p1')).called(1);
    expect(find.text('Esperando al administrador'), findsOneWidget);
    expect(find.byKey(const Key('taller-accept-p1')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Taller: aceptar con 409 muestra el motivo del back', (t) async {
    serve([live()]);
    when(repo.accept('p1'))
        .thenThrow(logic.fail(409, 'La propuesta ya no está vigente'));
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    await t.tap(find.byKey(const Key('taller-accept-p1')));
    await settle(t);
    expect(find.text('La propuesta ya no está vigente'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('No puedo: el motivo es obligatorio y rechaza sin alternativa',
      (t) async {
    await phone(t);
    serve([live()]);
    when(repo.reject('p1',
            reason: anyNamed('reason'),
            altStart: anyNamed('altStart'),
            altEnd: anyNamed('altEnd')))
        .thenAnswer((_) async =>
            MaintenanceProposal.fromJson(live(extra: {'status': 'rejected'})));
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    await t.tap(find.byKey(const Key('taller-reject-p1')));
    await settle(t);
    final submit = find.byKey(const Key('reject-submit'));
    expect(t.widget<SplgButton>(submit).onPressed, isNull,
        reason: 'sin motivo no se envía');
    await t.enterText(find.byType(TextField).first, 'Tengo turno médico');
    await t.pump();
    expect(t.widget<SplgButton>(submit).onPressed, isNotNull);
    serve([
      live(extra: {'status': 'rejected'})
    ]);
    await t.tap(submit);
    await settle(t);
    verify(repo.reject('p1',
            reason: 'Tengo turno médico', altStart: null, altEnd: null))
        .called(1);
    expect(find.byKey(const Key('taller-reject-p1')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('No puedo: con alternativa inviable muestra el error y no envía',
      (t) async {
    await phone(t);
    serve([live()]);
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    await t.tap(find.byKey(const Key('taller-reject-p1')));
    await settle(t);
    await t.enterText(find.byType(TextField).first, 'No puedo');
    await t.tap(find.byKey(const Key('reject-alt-toggle')));
    await settle(t);
    expect(find.byKey(const Key('reject-alt-day')), findsOneWidget);
    expect(find.byKey(const Key('reject-alt-start')), findsOneWidget);
    expect(find.textContaining('El taller atiende:'), findsOneWidget);
    expect(find.byKey(const Key('reject-alt-error')), findsOneWidget);
    expect(
        t.widget<SplgButton>(find.byKey(const Key('reject-submit'))).onPressed,
        isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Taller: confirmada por el administrador', (t) async {
    final board = locator<MaintenanceBoard>();
    serve([
      live(extra: {'status': 'accepted'})
    ]);
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    final start = DateTime.now().toUtc().add(const Duration(days: 3));
    board.handle(WindowConfirmed(ConfirmedWindow(
        caseId: 'c1',
        taskId: 't1',
        start: start,
        end: start.add(const Duration(hours: 4)),
        taskName: 'Service',
        patent: 'AB123CD')));
    await settle(t);
    expect(find.text('Confirmado'), findsOneWidget);
    expect(find.textContaining('no te ofrece pedidos'), findsOneWidget);
    expect(find.textContaining('no te va a ofrecer pedidos'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Taller: la confirmada de la API se ve al abrir, sin socket',
      (t) async {
    final start = DateTime.now().toUtc().add(const Duration(days: 4));
    serve([
      live(extra: {
        'status': 'accepted',
        'caseStatus': 'confirmed',
        'confirmedStart': start.toIso8601String(),
        'confirmedEnd': start.add(const Duration(hours: 4)).toIso8601String(),
      })
    ]);
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    expect(find.text('Confirmado'), findsOneWidget);
    expect(find.textContaining('no te ofrece pedidos'), findsOneWidget);
    expect(find.text('Esperando al administrador'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Taller: dos propuestas vigentes (Service y VTV) se responden por separado',
      (t) async {
    await phone(t);
    serve([
      live(id: 'p1'),
      live(
          id: 'p2', extra: {'taskName': 'VTV', 'taskId': 't2', 'caseId': 'c2'}),
    ]);
    when(repo.accept('p2')).thenAnswer((_) async {
      serve([
        live(id: 'p1'),
        live(id: 'p2', extra: {
          'status': 'accepted',
          'taskName': 'VTV',
          'taskId': 't2',
          'caseId': 'c2'
        })
      ]);
      return MaintenanceProposal.fromJson(live(id: 'p2'));
    });
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    expect(find.text('Para responder (2)'), findsOneWidget);
    expect(find.byKey(const Key('taller-accept-p1')), findsOneWidget);
    expect(find.byKey(const Key('taller-accept-p2')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('taller-accept-p2')));
    await t.tap(find.byKey(const Key('taller-accept-p2')));
    await settle(t);
    verify(repo.accept('p2')).called(1);
    verifyNever(repo.accept('p1'));
    expect(find.byKey(const Key('taller-accept-p1')), findsOneWidget,
        reason: 'la otra sigue para responder');
    expect(find.byKey(const Key('taller-accept-p2')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Taller: la confirmada muestra la ventana que fijó el administrador',
      (t) async {
    final start = DateTime.now().toUtc().add(const Duration(days: 4));
    serve([
      live(extra: {
        'status': 'accepted',
        'caseStatus': 'confirmed',
        'confirmedStart': start.toIso8601String(),
        'confirmedEnd': start.add(const Duration(hours: 4)).toIso8601String(),
      })
    ]);
    await t.pumpWidget(app(const TallerView()));
    await settle(t);
    expect(find.text('Confirmado'), findsOneWidget);
    expect(find.text(formatArDay(start)), findsOneWidget,
        reason: 'el día confirmado, no el de la ventana aceptada');
    await t.pumpWidget(const SizedBox());
  });

  group('convivencia con la oferta de pedido (rutas reales)', () {
    late MaintenanceNotifier notifier;
    late MaintenanceBoard board;

    // Se arma dentro del test: los eventos se entregan en la zona del
    // `start()`, que tiene que ser la del reloj falso.
    void begin() {
      notifier = MaintenanceNotifier(
        repo: repo,
        board: board,
        presenter: RouteNoticePresenter(),
        dialogs: locator<DialogService>(),
        openTallerRoute: () async {},
      )..start();
    }

    Future<void> pumpApp(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        navigatorKey: StackedService.navigatorKey,
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Text('INICIO')),
      ));
    }

    setUp(() => board = locator<MaintenanceBoard>());

    Future<void> end(WidgetTester t) async {
      notifier.dispose();
      await t.pumpWidget(const SizedBox());
    }

    testWidgets(
        'el aviso se cierra con la oferta arriba: la oferta sigue y no se rechaza',
        (t) async {
      await phone(t);
      begin();
      await pumpApp(t);
      board.handle(ProposalReceived(MaintenanceProposal.fromJson(live())));
      await settle(t);
      expect(find.byKey(const Key('maintenance-notice-text')), findsOneWidget);

      // La oferta de pedido (M1) se abre encima del aviso, como un diálogo.
      var offerResult = 'abierta';
      final ctx = StackedService.navigatorKey!.currentContext!;
      unawaited(showDialog<String>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Text('OFERTA DE PEDIDO')),
      ).then((r) => offerResult = r ?? 'rechazada'));
      await settle(t);
      expect(find.text('OFERTA DE PEDIDO'), findsOneWidget);

      // La propuesta se cierra con la oferta arriba.
      board.handle(const ProposalClosed('p1', 'expired'));
      await settle(t);

      expect(find.byKey(const Key('maintenance-notice-text')), findsNothing,
          reason: 'se cerró el aviso');
      expect(find.text('OFERTA DE PEDIDO'), findsOneWidget,
          reason: 'la oferta sigue en pantalla');
      expect(offerResult, 'abierta',
          reason: 'la oferta no se cerró ni rechazó');
      await end(t);
    });

    testWidgets(
        'con la oferta abierta el aviso se oculta y vuelve cuando se resuelve',
        (t) async {
      await phone(t);
      begin();
      await pumpApp(t);
      board.handle(ProposalReceived(MaintenanceProposal.fromJson(live())));
      await settle(t);
      expect(find.byKey(const Key('maintenance-notice-text')), findsOneWidget);
      notifier.offerStarted();
      await settle(t);
      expect(find.byKey(const Key('maintenance-notice-text')), findsNothing);
      notifier.offerEnded();
      await settle(t);
      expect(find.byKey(const Key('maintenance-notice-text')), findsOneWidget);
      await t.tap(find.byKey(const Key('maintenance-notice-later')));
      await settle(t);
      expect(find.byKey(const Key('maintenance-notice-text')), findsNothing);
      await end(t);
    });

    testWidgets('Aceptar en el aviso responde al back y cierra sólo el aviso',
        (t) async {
      await phone(t);
      begin();
      await pumpApp(t);
      when(repo.accept('p1')).thenAnswer((_) async =>
          MaintenanceProposal.fromJson(live(extra: {'status': 'accepted'})));
      serve([]);
      board.handle(ProposalReceived(MaintenanceProposal.fromJson(live())));
      await settle(t);
      await t.tap(find.byKey(const Key('maintenance-notice-accept')));
      await settle(t);
      verify(repo.accept('p1')).called(1);
      expect(find.byKey(const Key('maintenance-notice-text')), findsNothing);
      expect(find.text('INICIO'), findsOneWidget);
      await end(t);
    });

    testWidgets(
        'la hoja No puedo se cierra por su ruta aunque haya otro diálogo encima',
        (t) async {
      await phone(t);
      begin();
      serve([live()]);
      await t.pumpWidget(MaterialApp(
        navigatorKey: StackedService.navigatorKey,
        theme: AppTheme.lightTheme,
        home: const TallerView(),
      ));
      await settle(t);
      await t.tap(find.byKey(const Key('taller-reject-p1')));
      await settle(t);
      expect(find.byKey(const Key('reject-submit')), findsOneWidget);

      final ctx = StackedService.navigatorKey!.currentContext!;
      unawaited(showDialog<void>(
        context: ctx,
        builder: (_) => const AlertDialog(content: Text('OTRA COSA ARRIBA')),
      ));
      await settle(t);
      // La propuesta se cierra: la hoja desaparece, lo de arriba se queda.
      board.handle(const ProposalClosed('p1', 'expired'));
      await settle(t);
      await settle(t);
      expect(find.byKey(const Key('reject-submit')), findsNothing);
      expect(find.text('OTRA COSA ARRIBA'), findsOneWidget);
      await end(t);
    });

    testWidgets(
        'rechazar con la propuesta siguiente avisada antes de responder: se cierra la hoja y no se apila un aviso',
        (t) async {
      await phone(t);
      begin();
      serve([live(id: 'p1')]);
      when(repo.reject('p1',
              reason: anyNamed('reason'),
              altStart: anyNamed('altStart'),
              altEnd: anyNamed('altEnd')))
          .thenAnswer((_) async {
        // El back avisa la propuesta siguiente ANTES de responder el rechazo.
        board.handle(ProposalReceived(MaintenanceProposal.fromJson(
            live(id: 'p2', extra: {'taskId': 't2'}))));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return MaintenanceProposal.fromJson(
            live(id: 'p1', extra: {'status': 'rejected'}));
      });
      await t.pumpWidget(MaterialApp(
        navigatorKey: StackedService.navigatorKey,
        theme: AppTheme.lightTheme,
        home: const TallerView(),
      ));
      await settle(t);
      await t.tap(find.byKey(const Key('taller-reject-p1')));
      await settle(t);
      await t.enterText(find.byType(TextField).first, 'Tengo turno médico');
      await t.pump();
      serve([
        live(id: 'p1', extra: {'status': 'rejected'})
      ]);
      await t.tap(find.byKey(const Key('reject-submit')));
      await settle(t);
      await settle(t);
      expect(find.byKey(const Key('reject-submit')), findsNothing,
          reason: 'la hoja se cerró');
      expect(find.byKey(const Key('maintenance-notice-text')), findsNothing,
          reason: 'con Taller abierto no se apila un aviso encima: la '
              'propuesta nueva se ve en la lista');
      await end(t);
    });
  });

  group('capturas', () {
    Future<void> shot(WidgetTester t, String name) => expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

    testWidgets('pantalla Taller', (t) async {
      await phone(t);
      final fixed = DateTime.utc(2026, 11, 2, 13);
      serve([
        logic
            .json(expires: '2026-11-02T18:30:00.000Z', extra: {'urgent': true}),
        logic.json(
            id: 'p2',
            status: 'accepted',
            start: '2026-11-10T11:00:00.000Z',
            end: '2026-11-10T15:00:00.000Z'),
        logic.json(
            id: 'p3',
            status: 'rejected',
            extra: {'rejectionReason': 'Turno médico'}),
      ]);
      await t.pumpWidget(app(TallerView(clock: () => fixed)));
      await settle(t);
      expect(find.byKey(const Key('taller-countdown-p1')), findsOneWidget);
      await shot(t, 'taller');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('aviso de propuesta nueva', (t) async {
      await phone(t);
      final p =
          MaintenanceProposal.fromJson(logic.json(extra: {'urgent': true}));
      await t.pumpWidget(app(Scaffold(
          body: MaintenanceProposalDialog(proposal: p, onAction: (_) {}))));
      await settle(t);
      expect(find.byKey(const Key('maintenance-notice-text')), findsOneWidget);
      expect(find.text('Urgente'), findsOneWidget);
      await shot(t, 'taller_aviso');
    });
  });
}
