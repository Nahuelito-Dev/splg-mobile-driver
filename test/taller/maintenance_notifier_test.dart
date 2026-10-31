import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';

import '../helpers/test_helpers.mocks.dart';
import 'maintenance_logic_test.dart' as logic;

class FakeHandle implements NoticeHandle {
  FakeHandle(this.proposal);

  final MaintenanceProposal proposal;
  final _c = Completer<NoticeAction?>();
  bool dismissed = false;

  @override
  Future<NoticeAction?> get result => _c.future;

  @override
  void dismiss() {
    dismissed = true;
    if (!_c.isCompleted) _c.complete(null);
  }

  void choose(NoticeAction a) => _c.complete(a);
}

class FakePresenter implements NoticePresenter {
  final shown = <FakeHandle>[];

  /// Los que siguen en pantalla.
  List<FakeHandle> get visible =>
      shown.where((h) => !h.dismissed && !h._c.isCompleted).toList();

  @override
  NoticeHandle show(MaintenanceProposal proposal) {
    final h = FakeHandle(proposal);
    shown.add(h);
    return h;
  }
}

// Hoy: 2/11/2026 10:00 AR. Las propuestas vencen en horas.
final today = DateTime.utc(2026, 11, 2, 13);

MaintenanceProposal prop(String id, {String? expires, bool urgent = false}) =>
    MaintenanceProposal.fromJson(logic.json(
        id: id,
        expires: expires ?? '2026-11-03T13:00:00.000Z',
        extra: {'taskId': 't$id', 'urgent': urgent}));

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late MockMaintenanceRepository repo;
  late MockDialogService dialogs;
  late MaintenanceBoard board;
  late FakePresenter presenter;
  late MaintenanceNotifier n;
  late List<String> opened;
  var now = today;

  setUp(() {
    now = today;
    repo = MockMaintenanceRepository();
    dialogs = MockDialogService();
    board = MaintenanceBoard(now: () => now);
    presenter = FakePresenter();
    opened = [];
    n = MaintenanceNotifier(
      repo: repo,
      board: board,
      presenter: presenter,
      dialogs: dialogs,
      openTallerRoute: () async => opened.add('taller'),
      now: () => now,
    )..start();
  });
  tearDown(() => n.dispose());

  void emit(MaintenanceEvent e) => board.handle(e);

  group('propuesta nueva', () {
    test('se muestra, y Aceptar responde al back y refresca Taller', () async {
      when(repo.accept('p1')).thenAnswer((_) async => prop('p1'));
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenAnswer((_) async => const MaintenancePage());
      final changed = <MaintenanceEvent>[];
      board.events.listen(changed.add);
      emit(ProposalReceived(prop('p1')));
      await tick();
      expect(presenter.visible, hasLength(1));
      expect(n.shownProposalId, 'p1');
      presenter.visible.single.choose(NoticeAction.accept);
      await tick();
      verify(repo.accept('p1')).called(1);
      expect(changed.whereType<ProposalsChanged>(), isNotEmpty,
          reason: 'Taller abierto se relee');
      verify(dialogs.showDialog(
              title: 'Aceptaste el turno',
              description: anyNamed('description')))
          .called(1);
    });

    test('Aceptar con error del back lo muestra sin prefijo técnico', () async {
      when(repo.accept('p1')).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          response: Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 409,
              data: {'message': 'alternative: ya no está vigente'})));
      emit(ProposalReceived(prop('p1')));
      await tick();
      presenter.visible.single.choose(NoticeAction.accept);
      await tick();
      verify(dialogs.showDialog(
              title: 'No pudimos aceptar el turno',
              description: 'Ya no está vigente'))
          .called(1);
    });

    test('No puedo abre Taller; Después no hace nada', () async {
      emit(ProposalReceived(prop('p1')));
      await tick();
      presenter.visible.single.choose(NoticeAction.reject);
      await tick();
      expect(opened, ['taller']);
      emit(ProposalReceived(prop('p2')));
      await tick();
      presenter.visible.single.choose(NoticeAction.later);
      await tick();
      expect(opened, ['taller']);
      verifyNever(repo.accept(any));
    });

    test('con Taller abierto no se apila otra pantalla: se refresca', () async {
      board.tallerOpen = 1;
      final changed = <MaintenanceEvent>[];
      board.events.listen(changed.add);
      await n.openTaller();
      await tick();
      expect(opened, isEmpty);
      expect(changed.whereType<ProposalsChanged>(), hasLength(1));
    });

    test('el aviso trae «Urgente» del evento', () async {
      emit(ProposalReceived(prop('p1', urgent: true)));
      await tick();
      expect(presenter.visible.single.proposal.urgent, isTrue);
    });
  });

  group('varias a la vez', () {
    test('la segunda se encola y sale al resolver la primera; no se pisa',
        () async {
      emit(ProposalReceived(prop('p1')));
      emit(ProposalReceived(prop('p2')));
      emit(ProposalReceived(prop('p3')));
      await tick();
      expect(n.shownProposalId, 'p1');
      expect(n.queuedIds, ['p2', 'p3']);
      presenter.visible.single.choose(NoticeAction.later);
      await tick();
      expect(n.shownProposalId, 'p2');
      presenter.visible.single.choose(NoticeAction.later);
      await tick();
      expect(n.shownProposalId, 'p3');
    });

    test('una repetida no se duplica', () async {
      emit(ProposalReceived(prop('p1')));
      emit(ProposalReceived(prop('p1')));
      await tick();
      expect(presenter.shown, hasLength(1));
      expect(n.queuedIds, isEmpty);
    });
  });

  group('prioridad de la oferta de pedido', () {
    test('la oferta cierra el aviso por identidad y éste vuelve después',
        () async {
      emit(ProposalReceived(prop('p1')));
      await tick();
      final first = presenter.visible.single;
      n.offerStarted();
      expect(first.dismissed, isTrue, reason: 'se cerró ese aviso, no otro');
      expect(n.shownProposalId, isNull);
      expect(n.queuedIds, ['p1']);
      await tick();
      expect(presenter.shown, hasLength(1),
          reason: 'con la oferta no se muestra');
      n.offerEnded();
      await tick();
      expect(presenter.shown, hasLength(2));
      expect(presenter.visible.single.proposal.proposalId, 'p1');
      verifyNever(repo.accept(any));
    });

    test('con una oferta abierta, lo que llega espera', () async {
      n.offerStarted();
      emit(ProposalReceived(prop('p1')));
      await tick();
      expect(presenter.shown, isEmpty);
      n.offerEnded();
      await tick();
      expect(presenter.visible, hasLength(1));
    });

    test('los avisos informativos también esperan a la oferta', () async {
      n.offerStarted();
      emit(CaseEscalated(caseId: 'c1', taskName: 'Frenos', patent: 'AB123CD'));
      await tick();
      verifyNever(dialogs.showDialog(
          title: anyNamed('title'), description: anyNamed('description')));
      n.offerEnded();
      await tick();
      verify(dialogs.showDialog(
              title: 'El taller pasó al administrador',
              description: argThat(contains('Frenos'), named: 'description')))
          .called(1);
    });
  });

  group('hoja «No puedo» abierta', () {
    test('los avisos nuevos esperan hasta que se cierra', () async {
      n.sheetOpened();
      emit(ProposalReceived(prop('p2')));
      await tick();
      expect(presenter.shown, isEmpty);
      n.sheetClosed();
      await tick();
      expect(presenter.visible.single.proposal.proposalId, 'p2');
    });
  });

  group('cierre y vencimiento', () {
    test('si la propuesta se cierra con el aviso abierto, se cierra ese aviso',
        () async {
      emit(ProposalReceived(prop('p1')));
      emit(ProposalReceived(prop('p2')));
      await tick();
      final first = presenter.visible.single;
      emit(const ProposalClosed('p1', 'cancelled'));
      await tick();
      expect(first.dismissed, isTrue);
      expect(n.shownProposalId, 'p2', reason: 'sigue la que estaba esperando');
    });

    test('una encolada que se cierra no aparece', () async {
      emit(ProposalReceived(prop('p1')));
      emit(ProposalReceived(prop('p2')));
      await tick();
      emit(const ProposalClosed('p2', 'expired'));
      presenter.visible.single.choose(NoticeAction.later);
      await tick();
      expect(presenter.shown, hasLength(1));
    });

    test('el aviso vence solo con expiresAt', () async {
      final soon = DateTime.now().toUtc().add(const Duration(milliseconds: 80));
      final real = MaintenanceNotifier(
        repo: repo,
        board: board,
        presenter: presenter,
        dialogs: dialogs,
        openTallerRoute: () async {},
      )..start();
      board.handle(ProposalReceived(MaintenanceProposal.fromJson(logic.json(
          id: 'pe',
          expires: soon.toIso8601String(),
          extra: {'taskId': 'te'}))));
      await tick();
      final h = presenter.shown.last;
      expect(h.dismissed, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(h.dismissed, isTrue);
      expect(real.pending, isEmpty);
      real.dispose();
    });

    test('la diferida vencida no se muestra', () async {
      n.offerStarted();
      emit(ProposalReceived(prop('p1', expires: '2026-11-02T16:00:00.000Z')));
      now = DateTime.utc(2026, 11, 2, 17);
      n.offerEnded();
      await tick();
      expect(presenter.shown, isEmpty);
    });
  });

  group('lectura de pendientes', () {
    MaintenancePage page(List<MaintenanceProposal> l) =>
        MaintenancePage(proposals: l, total: l.length);

    test('en línea muestra la vigente que dejó el cron y no la repite',
        () async {
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenAnswer((_) async => page([prop('p1')]));
      await n.sync();
      await tick();
      expect(presenter.visible.single.proposal.proposalId, 'p1');
      presenter.visible.single.choose(NoticeAction.later);
      await tick();
      await n.sync();
      await tick();
      expect(presenter.shown, hasLength(1), reason: 'ya la vio');
      expect(n.pending, hasLength(1), reason: 'la marca del Inicio sigue');
    });

    test('fuera de línea sólo alimenta la marca', () async {
      n.stop();
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenAnswer((_) async => page([prop('p1'), prop('p2')]));
      var changes = 0;
      n.changes.listen((_) => changes++);
      await n.sync();
      await tick();
      expect(presenter.shown, isEmpty);
      expect(n.pending, hasLength(2));
      expect(changes, greaterThan(0));
    });

    test('las vencidas no cuentan', () async {
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenAnswer((_) async =>
              page([prop('p1', expires: '2026-11-02T12:00:00.000Z')]));
      await n.sync();
      expect(n.pending, isEmpty);
      expect(presenter.shown, isEmpty);
    });

    test('un error de red no rompe nada', () async {
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '')));
      await n.sync();
      expect(n.pending, isEmpty);
    });

    test('reset (cierre de sesión) descarta lo pendiente y lo que se veía',
        () async {
      emit(ProposalReceived(prop('p1')));
      await tick();
      final h = presenter.visible.single;
      n.reset();
      expect(h.dismissed, isTrue);
      expect(n.pending, isEmpty);
      expect(n.queuedIds, isEmpty);
    });
  });

  group('avisos informativos', () {
    test('ventana confirmada avisa que no habrá pedidos', () async {
      emit(WindowConfirmed(ConfirmedWindow(
          caseId: 'c1',
          start: DateTime.utc(2026, 11, 4, 11),
          end: DateTime.utc(2026, 11, 4, 15),
          taskName: 'Service',
          patent: 'AB123CD')));
      await tick();
      verify(dialogs.showDialog(
              title: 'Taller confirmado',
              description: argThat(contains('no te va a ofrecer pedidos'),
                  named: 'description')))
          .called(1);
    });
  });

  group('ronda 4: nada del taller sobre una oferta ni un pedido en curso', () {
    test('abrir Taller con una oferta abierta espera y se ejecuta al terminar',
        () async {
      n.offerStarted();
      await n.openTaller();
      expect(opened, isEmpty);
      n.offerEnded();
      await tick();
      expect(opened, ['taller']);
      n.offerEnded();
      await tick();
      expect(opened, ['taller'], reason: 'una sola vez');
    });

    test('abrir Taller con un pedido en curso espera hasta recheck', () async {
      var busy = true;
      n.isBusyWithOrder = () => busy;
      await n.openTaller();
      expect(opened, isEmpty);
      busy = false;
      n.recheck();
      await tick();
      expect(opened, ['taller']);
    });

    test('un aviso con un pedido en curso no aparece hasta que termina',
        () async {
      var busy = true;
      n.isBusyWithOrder = () => busy;
      emit(ProposalReceived(prop('p1')));
      emit(CaseEscalated(caseId: 'c', taskName: 'Frenos'));
      await tick();
      expect(presenter.shown, isEmpty);
      verifyNever(dialogs.showDialog(
          title: anyNamed('title'), description: anyNamed('description')));
      busy = false;
      n.recheck();
      await tick();
      expect(presenter.visible, hasLength(1));
    });

    test('con la oferta terminada pero un pedido por retomar, espera',
        () async {
      var busy = false;
      n.isBusyWithOrder = () => busy;
      n.offerStarted();
      emit(ProposalReceived(prop('p1')));
      await tick();
      n.offerEnded(pump: false);
      await tick();
      expect(presenter.shown, isEmpty);
      busy = true;
      n.recheck();
      await tick();
      expect(presenter.shown, isEmpty);
      busy = false;
      n.recheck();
      await tick();
      expect(presenter.visible, hasLength(1));
    });

    test('responder desde Taller cierra el aviso visible de esa propuesta',
        () async {
      emit(ProposalReceived(prop('p1')));
      emit(ProposalReceived(prop('p2')));
      await tick();
      final first = presenter.visible.single;
      board.notifyChanged('p1');
      await tick();
      expect(first.dismissed, isTrue, reason: 'daría un 409');
      expect(n.shownProposalId, 'p2');
      board.notifyChanged('p2');
      await tick();
      expect(presenter.visible, isEmpty);
    });

    test(
        'con Taller abierto no se apila un aviso (ni al volver a primer plano)',
        () async {
      board.tallerOpen = 1;
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenAnswer(
              (_) async => MaintenancePage(proposals: [prop('p1')], total: 1));
      await n.sync();
      emit(ProposalReceived(prop('p2')));
      await tick();
      expect(presenter.shown, isEmpty);
      expect(n.pending, hasLength(2), reason: 'la marca sigue');
    });
  });

  group('ronda 4: estado de la sesión', () {
    MaintenancePage page(List<MaintenanceProposal> l) =>
        MaintenancePage(proposals: l, total: l.length);

    test(
        'Después se conserva al volver a línea; lo oculto por otra cosa vuelve',
        () async {
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenAnswer((_) async => page([prop('p1'), prop('p2')]));
      await n.sync();
      await tick();
      presenter.visible.single.choose(NoticeAction.later); // p1: Después
      await tick();
      expect(n.shownProposalId, 'p2');
      // Queda fuera de línea con p2 en pantalla (sin decidir) y vuelve.
      n.stop();
      n.start();
      await n.sync();
      await tick();
      final ids = presenter.shown.map((h) => h.proposal.proposalId).toList();
      expect(ids, ['p1', 'p2', 'p2'],
          reason: 'p1 postergada no vuelve sola; p2 sin decidir sí');
    });

    test('el cierre de sesión olvida lo postergado de ese chofer', () async {
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenAnswer((_) async => page([prop('p1')]));
      await n.sync();
      await tick();
      presenter.visible.single.choose(NoticeAction.later);
      await tick();
      n.reset();
      n.start();
      await n.sync();
      await tick();
      expect(presenter.shown, hasLength(2),
          reason: 'otro chofer o sesión nueva');
    });

    test('stop no pone en cero la oferta ni la hoja que siguen abiertas',
        () async {
      n.offerStarted();
      n.sheetOpened();
      n.stop();
      n.start();
      emit(ProposalReceived(prop('p1')));
      await tick();
      expect(presenter.shown, isEmpty, reason: 'la oferta sigue abierta');
      n.offerEnded();
      await tick();
      expect(presenter.shown, isEmpty, reason: 'la hoja sigue abierta');
      n.sheetClosed();
      await tick();
      expect(presenter.visible, hasLength(1));
    });

    test('una lectura que llega después de reset se descarta', () async {
      final late = Completer<MaintenancePage>();
      when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
          .thenAnswer((_) => late.future);
      final f = n.sync();
      n.reset(); // cierre de sesión / cambio de chofer
      late.complete(page([prop('p1')]));
      await f;
      await tick();
      expect(n.pending, isEmpty);
      expect(presenter.shown, isEmpty);
    });

    test('una propuesta reemitida con datos nuevos actualiza lo que se muestra',
        () async {
      emit(ProposalReceived(prop('p1')));
      await tick();
      final old = presenter.visible.single;
      emit(ProposalReceived(prop('p1', urgent: true)));
      await tick();
      expect(old.dismissed, isTrue);
      expect(presenter.visible.single.proposal.urgent, isTrue);
      expect(presenter.shown, hasLength(2));
      // La misma, sin cambios, no vuelve a mostrarse.
      emit(ProposalReceived(prop('p1', urgent: true)));
      await tick();
      expect(presenter.shown, hasLength(2));
    });

    test('reemitida estando en la cola: se reemplaza; postergada: vuelve',
        () async {
      emit(ProposalReceived(prop('p1')));
      emit(ProposalReceived(prop('p2')));
      await tick();
      emit(ProposalReceived(prop('p2', urgent: true)));
      await tick();
      expect(n.queuedIds, ['p2']);
      presenter.visible.single.choose(NoticeAction.later); // p1 postergada
      await tick();
      expect(presenter.visible.single.proposal.urgent, isTrue,
          reason: 'p2 nueva');
      presenter.visible.single.choose(NoticeAction.later);
      await tick();
      emit(ProposalReceived(prop('p1', urgent: true)));
      await tick();
      expect(presenter.visible.single.proposal.proposalId, 'p1');
    });
  });
}
