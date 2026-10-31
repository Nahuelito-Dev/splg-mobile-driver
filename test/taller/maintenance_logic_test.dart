import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_repository.dart';
import 'package:splg_driver/ui/views/taller/reject_proposal_viewmodel.dart';
import 'package:splg_driver/ui/views/taller/taller_viewmodel.dart';

import '../helpers/test_helpers.mocks.dart';

DioException fail(int status, String message) => DioException(
    requestOptions: RequestOptions(path: ''),
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: status,
        data: {'message': message}));

// "Hoy" para todos los tests: lunes 2/11/2026, 10:00 hora argentina.
final today = DateTime.utc(2026, 11, 2, 13);

Map<String, dynamic> json({
  String id = 'p1',
  String status = 'pending',
  String start = '2026-11-04T11:00:00.000Z',
  String end = '2026-11-04T15:00:00.000Z',
  String expires = '2026-11-03T13:00:00.000Z',
  Map<String, dynamic> extra = const {},
}) =>
    {
      'proposalId': id,
      'caseId': 'c1',
      'taskId': 't1',
      'taskName': 'Service: aceite y filtros',
      'carId': 'car1',
      'patent': 'AB123CD',
      'windowStart': start,
      'windowEnd': end,
      'rank': 1,
      'status': status,
      'expiresAt': expires,
      'respondedAt': null,
      'rejectionReason': null,
      'altWindowStart': null,
      'altWindowEnd': null,
      ...extra,
    };

const confirmedExtra = {
  'caseStatus': 'confirmed',
  'confirmedStart': '2026-11-04T11:00:00.000Z',
  'confirmedEnd': '2026-11-04T15:00:00.000Z',
};

MaintenanceProposal proposal({String status = 'pending'}) =>
    MaintenanceProposal.fromJson(json(status: status));

const settings = MaintenanceSettings(
  workshopStartHour: 8,
  workshopEndHour: 13,
  workshopDays: [1, 2, 3, 4, 5, 6],
  holidays: ['2026-11-23'],
  minLeadDays: 1,
  horizonDays: 30,
  proposalTtlHours: 24,
);

extension on TallerViewModel {
  MaintenanceProposal? get current => open.isEmpty ? null : open.first;
}

void main() {
  group('modelos', () {
    test('parsea la propuesta del contrato', () {
      final p = MaintenanceProposal.fromJson(json(extra: {
        'urgent': true,
        'status': 'rejected',
        'rejectionReason': 'turno médico',
        'altWindowStart': '2026-11-05T11:00:00.000Z',
        'altWindowEnd': '2026-11-05T15:00:00.000Z',
      }));
      expect(p.proposalId, 'p1');
      expect(p.patent, 'AB123CD');
      expect(p.taskName, 'Service: aceite y filtros');
      expect(p.status, ProposalStatus.rejected);
      expect(p.urgent, isTrue);
      expect(p.hasAlternative, isTrue);
      expect(p.windowStart, DateTime.utc(2026, 11, 4, 11));
      expect(p.rank, 1);
    });

    test('el payload del socket trae menos campos y no rompe', () {
      final p = MaintenanceProposal.fromJson({
        'proposalId': 'p2',
        'taskId': 't1',
        'windowStart': '2026-11-04T11:00:00.000Z',
        'windowEnd': '2026-11-04T15:00:00.000Z',
        'expiresAt': '2026-11-03T13:00:00.000Z',
        'taskName': 'Service',
        'patent': null,
      });
      expect(p.status, ProposalStatus.pending);
      expect(p.caseId, isNull);
      expect(p.vehicleLabel, 'tu vehículo');
      expect(p.urgent, isFalse);
    });

    test('vigente, vencida y pasada según el reloj', () {
      final p = proposal();
      expect(p.isOpen(today), isTrue);
      expect(p.isOpen(DateTime.utc(2026, 11, 3, 13)), isFalse);
      expect(p.isLapsed(DateTime.utc(2026, 11, 3, 14)), isTrue);
      expect(proposal(status: 'accepted').isLapsed(today), isFalse);
      expect(p.isPast(DateTime.utc(2026, 11, 4, 16)), isTrue);
    });

    test('la ventana se muestra en hora argentina', () {
      final p = proposal();
      expect(formatWindow(p.windowStart, p.windowEnd),
          'Miércoles 4 de noviembre de 08:00 a 12:00');
    });

    test('la ventana confirmada es la que informa el back, no la aceptada', () {
      final p = MaintenanceProposal.fromJson(json(status: 'accepted', extra: {
        'caseStatus': 'confirmed',
        'confirmedStart': '2026-11-06T11:00:00.000Z',
        'confirmedEnd': '2026-11-06T15:00:00.000Z',
        'projectedDueAt': '2026-11-20T03:00:00.000Z',
      }));
      expect(p.caseConfirmed, isTrue);
      expect(p.projectedDueAt, DateTime.utc(2026, 11, 20, 3));
      final w = p.confirmedWindow(today)!;
      expect(w.start, DateTime.utc(2026, 11, 6, 11));
      expect(w.caseId, 'c1');
      expect(p.confirmedWindow(DateTime.utc(2026, 11, 7)), isNull,
          reason: 'el turno ya pasó');
    });

    test(
        'un caso escalado que el admin confirmó cuenta con cualquier propuesta',
        () {
      final p = MaintenanceProposal.fromJson(
          json(status: 'expired', extra: confirmedExtra));
      expect(p.confirmedWindow(today), isNotNull);
    });

    test('sin ventana confirmada o sin caseStatus no hay confirmación', () {
      expect(
          MaintenanceProposal.fromJson(
                  json(status: 'accepted', extra: {'caseStatus': 'confirmed'}))
              .confirmedWindow(today),
          isNull);
      expect(proposal(status: 'accepted').confirmedWindow(today), isNull);
    });

    test('espera al administrador sólo con el caso vivo y sin confirmar', () {
      MaintenanceProposal p(String? cs) => MaintenanceProposal.fromJson(
          json(status: 'accepted', extra: {'caseStatus': cs}));
      expect(p('awaiting_confirmation').isWaitingAdmin(today), isTrue);
      expect(p(null).isWaitingAdmin(today), isTrue);
      expect(p('confirmed').isWaitingAdmin(today), isFalse);
      expect(p('cancelled').isWaitingAdmin(today), isFalse);
      expect(p('escalated').isWaitingAdmin(today), isFalse);
    });

    test('parsea el horario del taller', () {
      final s = MaintenanceSettings.fromJson({
        'workshopStartHour': 8,
        'workshopEndHour': 13,
        'workshopDays': [1, 2, 3, 4, 5, 6],
        'holidays': ['2026-11-23'],
        'minLeadDays': 1,
        'horizonDays': 30,
        'proposalTtlHours': 24,
      });
      expect(s.workshopDays, [1, 2, 3, 4, 5, 6]);
      expect(s.holidays, ['2026-11-23']);
      expect(s.scheduleText, 'lun, mar, mié, jue, vie, sáb, de 08:00 a 13:00');
    });
  });

  group('validación de la ventana alternativa', () {
    String? check(DateTime? day, int? from, int? to) =>
        settings.validateAlternative(day, from, to, today);

    test('una ventana dentro del horario es viable', () {
      expect(check(DateTime.utc(2026, 11, 5), 9 * 60, 12 * 60), isNull);
      expect(check(DateTime.utc(2026, 11, 5), 8 * 60, 13 * 60), isNull,
          reason: 'los bordes del horario valen');
    });

    test('falta el día o la hora', () {
      expect(check(null, 540, 600), 'Elegí el día.');
      expect(check(DateTime.utc(2026, 11, 5), null, 600),
          'Elegí el horario de inicio y de fin.');
    });

    test('domingo: el taller no atiende', () {
      expect(check(DateTime.utc(2026, 11, 8), 540, 600),
          startsWith('El taller no atiende ese día'));
    });

    test('feriado', () {
      expect(
          check(DateTime.utc(2026, 11, 23), 540, 600), 'Ese día es feriado.');
    });

    test('aviso mínimo: mañana sí, hoy no', () {
      expect(check(DateTime.utc(2026, 11, 3), 540, 600), isNull);
      expect(check(DateTime.utc(2026, 11, 2), 540, 600),
          'Necesitamos al menos un día de aviso.');
    });

    test('horizonte', () {
      expect(check(DateTime.utc(2026, 12, 2), 540, 600), isNull);
      expect(check(DateTime.utc(2026, 12, 3), 540, 600),
          'Elegí una fecha dentro de los próximos 30 días.');
    });

    test('horario del taller y orden', () {
      expect(check(DateTime.utc(2026, 11, 5), 7 * 60, 10 * 60),
          contains('entre las 08:00 y las 13:00'));
      expect(check(DateTime.utc(2026, 11, 5), 9 * 60, 14 * 60),
          contains('entre las 08:00 y las 13:00'));
      expect(check(DateTime.utc(2026, 11, 5), 10 * 60, 10 * 60),
          'El fin tiene que ser después del inicio.');
      expect(check(DateTime.utc(2026, 11, 5), 11 * 60, 10 * 60),
          'El fin tiene que ser después del inicio.');
    });

    test('el día de hoy en hora argentina, no en UTC', () {
      // 01:00 UTC del 3/11 es todavía el 2/11 a las 22:00 en Argentina.
      final late = DateTime.utc(2026, 11, 3, 1);
      expect(
          settings.validateAlternative(
              DateTime.utc(2026, 11, 3), 540, 600, late),
          isNull);
      expect(argentinaDay(late), DateTime.utc(2026, 11, 2));
    });

    test('con aviso 0, una hora que ya pasó no sirve', () {
      const s = MaintenanceSettings(
          workshopStartHour: 8,
          workshopEndHour: 13,
          workshopDays: [1, 2, 3, 4, 5, 6],
          holidays: [],
          minLeadDays: 0,
          horizonDays: 30,
          proposalTtlHours: 24);
      expect(
          s.validateAlternative(
              DateTime.utc(2026, 11, 2), 8 * 60, 9 * 60, today),
          'Esa hora ya pasó.');
      expect(
          s.validateAlternative(
              DateTime.utc(2026, 11, 2), 11 * 60, 12 * 60, today),
          isNull);
    });

    test('isSelectableDay filtra el calendario', () {
      expect(
          settings.isSelectableDay(DateTime.utc(2026, 11, 3), today), isTrue);
      expect(
          settings.isSelectableDay(DateTime.utc(2026, 11, 8), today), isFalse);
      expect(
          settings.isSelectableDay(DateTime.utc(2026, 11, 23), today), isFalse);
      expect(
          settings.isSelectableDay(DateTime.utc(2026, 11, 2), today), isFalse);
    });

    test('toUtc convierte la hora argentina', () {
      expect(MaintenanceSettings.toUtc(DateTime.utc(2026, 11, 5), 9 * 60),
          DateTime.utc(2026, 11, 5, 12));
    });
  });

  group('selector de días y mensajes', () {
    test('sólo días anteriores al vencimiento proyectado', () {
      final due = DateTime.utc(2026, 11, 6, 3); // vence el 6/11 (hora AR)
      final days = settings.selectableDays(today, due: due);
      expect(days.map((d) => d.day), [3, 4, 5],
          reason: 'desde mañana (aviso 1 día) y antes del día del vencimiento');
      expect(
          settings.isSelectableDay(DateTime.utc(2026, 11, 6), today, due: due),
          isFalse);
      expect(
          settings.validateAlternative(
              DateTime.utc(2026, 11, 9), 540, 600, today,
              due: due),
          'Elegí un día anterior al vencimiento de la tarea.');
    });

    test('si ninguno llega a tiempo se admiten todos, como el back', () {
      final due = DateTime.utc(2026, 11, 2); // ya vencida
      expect(settings.selectableDays(today, due: due), isNotEmpty);
      expect(
          settings.isSelectableDay(DateTime.utc(2026, 11, 9), today, due: due),
          isTrue);
    });

    test('cleanApiMessage saca el prefijo técnico del campo', () {
      expect(
          cleanApiMessage(
              'alternative: el día tiene que ser posterior al aviso'),
          'El día tiene que ser posterior al aviso');
      expect(cleanApiMessage('reason: indicá el motivo'), 'Indicá el motivo');
      expect(cleanApiMessage('La propuesta ya no está vigente'),
          'La propuesta ya no está vigente');
      expect(cleanApiMessage('No hay conexión: reintentá'),
          'No hay conexión: reintentá');
    });
  });

  group('MaintenanceBoard', () {
    ConfirmedWindow window({String caseId = 'c1', DateTime? end}) =>
        ConfirmedWindow(
            caseId: caseId,
            taskId: 't1',
            start: DateTime.utc(2026, 11, 4, 11),
            end: end ?? DateTime.utc(2026, 11, 4, 15),
            taskName: 'Service',
            patent: 'AB123CD');

    test('recuerda las confirmadas y se las da a quien escucha ya al día',
        () async {
      final b = MaintenanceBoard(now: () => today);
      final seen = <int>[];
      b.events.listen((_) => seen.add(b.confirmed.length));
      b.handle(WindowConfirmed(window()));
      b.handle(WindowConfirmed(window())); // el mismo caso no se duplica
      await Future<void>.delayed(Duration.zero);
      expect(seen, [1, 1]);
      expect(b.confirmed, hasLength(1));
    });

    test('las que ya pasaron y las escaladas salen', () {
      var now = today;
      final b = MaintenanceBoard(now: () => now);
      b.handle(WindowConfirmed(window()));
      b.handle(WindowConfirmed(window(caseId: 'c2')));
      b.handle(const CaseEscalated(caseId: 'c2', taskName: 'Service'));
      expect(b.confirmed.map((w) => w.caseId), ['c1']);
      now = DateTime.utc(2026, 11, 5);
      expect(b.confirmed, isEmpty);
    });

    test('bind con otro chofer, o reset, descarta lo del anterior', () {
      final b = MaintenanceBoard(now: () => today);
      b.bind('u1');
      b.handle(WindowConfirmed(window()));
      b.bind('u1');
      expect(b.confirmed, hasLength(1));
      b.bind('u2');
      expect(b.confirmed, isEmpty, reason: 'otro chofer');
      b.handle(WindowConfirmed(window()));
      b.reset();
      expect(b.confirmed, isEmpty);
    });

    test('attach re-emite lo del socket y detach lo suelta', () async {
      final b = MaintenanceBoard(now: () => today);
      final src = StreamController<MaintenanceEvent>();
      final got = <MaintenanceEvent>[];
      b.events.listen(got.add);
      b.attach(src.stream);
      src.add(ProposalReceived(proposal()));
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(1));
      b.detach();
      src.add(ProposalReceived(proposal()));
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(1));
      await src.close();
    });
  });

  group('TallerViewModel', () {
    late MockMaintenanceRepository repo;
    late MaintenanceBoard board;
    late TallerViewModel m;
    var now = today;

    setUp(() {
      now = today;
      repo = MockMaintenanceRepository();
      board = MaintenanceBoard(now: () => now);
      when(repo.settings()).thenAnswer((_) async => settings);
      m = TallerViewModel(repo: repo, board: board, now: () => now);
    });
    tearDown(() => m.dispose());

    void page(List<Map<String, dynamic>> items) =>
        when(repo.proposals()).thenAnswer((_) async => MaintenancePage(
            proposals: [for (final j in items) MaintenanceProposal.fromJson(j)],
            total: items.length));

    test('separa la vigente, lo que espera, el historial y la cuenta regresiva',
        () async {
      page([
        json(id: 'p1'),
        json(
            id: 'p2',
            status: 'accepted',
            start: '2026-11-10T11:00:00.000Z',
            end: '2026-11-10T15:00:00.000Z'),
        json(id: 'p3', status: 'rejected', extra: {'rejectionReason': 'x'}),
        json(id: 'p4', status: 'expired'),
        json(
            id: 'p5',
            status: 'accepted',
            start: '2026-10-01T11:00:00.000Z',
            end: '2026-10-01T15:00:00.000Z'),
      ]);
      await m.load();
      expect(m.current!.proposalId, 'p1');
      expect(m.waiting.map((p) => p.proposalId), ['p2']);
      expect(m.history.map((p) => p.proposalId), ['p3', 'p4', 'p5']);
      expect(m.secondsLeft(m.current!), 24 * 3600);
      expect(m.settings, isNotNull);
      expect(m.loadError, isNull);
    });

    test('una rechazada con otra ventana espera al administrador', () async {
      page([
        json(status: 'rejected', extra: {
          'altWindowStart': '2026-11-10T11:00:00.000Z',
          'altWindowEnd': '2026-11-10T15:00:00.000Z',
        })
      ]);
      await m.load();
      expect(m.waiting, hasLength(1));
      expect(m.current, isNull);
    });

    test('una vigente que ya pasó su vencimiento figura como vencida',
        () async {
      page([json()]);
      await m.load();
      now = DateTime.utc(2026, 11, 3, 14);
      expect(m.current, isNull);
      expect(m.history, hasLength(1));
      expect(m.statusLabel(m.history.first), 'Vencida');
      expect(m.secondsLeft(m.history.first), 0);
    });

    test('sin turnos: vacío', () async {
      page([]);
      await m.load();
      expect(m.isEmpty, isTrue);
    });

    test('si falla la lectura queda el error para reintentar', () async {
      when(repo.proposals()).thenThrow(fail(500, 'caído'));
      await m.load();
      expect(m.loadError, isNotNull);
    });

    test('sin el horario igual carga y avisa que no se puede proponer',
        () async {
      page([json()]);
      when(repo.settings()).thenThrow(fail(500, 'x'));
      await m.load();
      expect(m.current, isNotNull);
      expect(m.settings, isNull);
      expect(m.settingsError, isNotNull);
    });

    test('aceptar manda la respuesta y pasa a esperar al administrador',
        () async {
      page([json()]);
      when(repo.accept('p1')).thenAnswer((_) async {
        page([json(status: 'accepted')]);
        return MaintenanceProposal.fromJson(json(status: 'accepted'));
      });
      await m.load();
      await m.accept(m.current!);
      verify(repo.accept('p1')).called(1);
      expect(m.current, isNull);
      expect(m.waiting.single.proposalId, 'p1');
      expect(m.failure, isNull);
      expect(m.notice, contains('administrador'));
    });

    test('aceptar con 409: muestra el motivo y relee', () async {
      page([json()]);
      when(repo.accept('p1'))
          .thenThrow(fail(409, 'La propuesta ya no está vigente'));
      await m.load();
      page([json(status: 'expired')]);
      await m.accept(m.current ?? proposal());
      expect(m.failure, 'La propuesta ya no está vigente');
      expect(m.current, isNull);
      verify(repo.proposals()).called(2);
    });

    test('rechazada: queda registrada y se relee', () async {
      page([json()]);
      await m.load();
      m.onRejected(MaintenanceProposal.fromJson(json(status: 'rejected')));
      expect(m.current, isNull);
      expect(m.notice, contains('rechazo'));
    });

    test('eventos: cierra sola la propuesta que vence o se cancela', () async {
      page([json()]);
      await m.load();
      m.init();
      page([json(status: 'cancelled')]);
      board.handle(const ProposalClosed('p1', 'cancelled'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(m.current, isNull);
      expect(m.history.single.status, ProposalStatus.cancelled);
    });

    test('eventos: ventana confirmada aparece y avisa que no hay pedidos',
        () async {
      page([json(status: 'accepted')]);
      await m.load();
      m.init();
      board.handle(WindowConfirmed(ConfirmedWindow(
          caseId: 'c1',
          taskId: 't1',
          start: DateTime.utc(2026, 11, 4, 11),
          end: DateTime.utc(2026, 11, 4, 15),
          taskName: 'Service',
          patent: 'AB123CD')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(m.confirmed, hasLength(1));
      expect(m.waiting, isEmpty, reason: 'ya no está esperando');
      expect(m.notice, contains('no te va a ofrecer pedidos'));
    });

    test('la ventana confirmada sale de la API, sin avisos del socket',
        () async {
      page([
        json(id: 'p1', status: 'accepted', extra: confirmedExtra),
        json(id: 'p0', status: 'rejected', extra: confirmedExtra),
      ]);
      await m.load();
      expect(board.confirmed, isEmpty);
      expect(m.confirmed.single.caseId, 'c1', reason: 'un caso, una ventana');
      expect(m.confirmed.single.start, DateTime.utc(2026, 11, 4, 11));
      expect(m.waiting, isEmpty);
      expect(m.history.map((p) => p.proposalId), ['p0']);
    });

    test('un caso escalado que el admin confirmó figura confirmado', () async {
      page([json(status: 'expired', extra: confirmedExtra)]);
      await m.load();
      expect(m.confirmed, hasLength(1));
    });

    test('dos propuestas vigentes a la vez (una por tarea) salen las dos',
        () async {
      page([
        json(id: 'p1', expires: '2026-11-03T13:00:00.000Z'),
        json(
            id: 'p2',
            expires: '2026-11-02T20:00:00.000Z',
            extra: {'taskId': 't2', 'caseId': 'c2'}),
      ]);
      await m.load();
      expect(m.open.map((p) => p.proposalId), ['p2', 'p1'],
          reason: 'la que vence antes, primero');
    });

    test('lee todas las páginas para que nada quede fuera', () async {
      when(repo.proposals(limit: 50, offset: 0)).thenAnswer((_) async =>
          MaintenancePage(proposals: [
            for (var i = 0; i < 50; i++)
              MaintenanceProposal.fromJson(json(id: 'h$i', status: 'rejected')),
          ], total: 52));
      when(repo.proposals(limit: 50, offset: 50))
          .thenAnswer((_) async => MaintenancePage(proposals: [
                MaintenanceProposal.fromJson(json(
                    id: 'w1',
                    status: 'accepted',
                    start: '2026-11-10T11:00:00.000Z',
                    end: '2026-11-10T15:00:00.000Z')),
                MaintenanceProposal.fromJson(json(id: 'o1')),
              ], total: 52));
      await m.load();
      expect(m.open.single.proposalId, 'o1');
      expect(m.waiting.single.proposalId, 'w1');
      expect(m.history, hasLength(50));
    });

    test('el historial va del más nuevo al más viejo', () async {
      page([
        json(id: 'a', status: 'rejected', expires: '2026-10-01T10:00:00.000Z'),
        json(id: 'b', status: 'rejected', expires: '2026-10-20T10:00:00.000Z'),
        json(id: 'c', status: 'expired', expires: '2026-10-10T10:00:00.000Z'),
      ]);
      await m.load();
      expect(m.history.map((p) => p.proposalId), ['b', 'c', 'a']);
    });

    test('la marca Urgente viene de la API y sólo vale mientras espera',
        () async {
      page([
        json(extra: {'urgent': true})
      ]);
      await m.load();
      expect(m.isUrgent(m.current!), isTrue);
      now = DateTime.utc(2026, 11, 3, 14);
      expect(m.isUrgent(proposal()), isFalse);
    });

    test('tener la pantalla abierta se registra en el tablero', () async {
      page([]);
      await m.load();
      expect(board.tallerOpen, 0);
      m.init();
      expect(board.tallerOpen, 1);
      m.dispose();
      expect(board.tallerOpen, 0);
      m = TallerViewModel(repo: repo, board: board, now: () => now);
    });

    test('aceptada con el caso cancelado o escalado va al historial', () async {
      page([
        json(id: 'p1', status: 'accepted', extra: {'caseStatus': 'cancelled'}),
        json(id: 'p2', status: 'accepted', extra: {'caseStatus': 'escalated'}),
      ]);
      await m.load();
      expect(m.waiting, isEmpty);
      expect(m.confirmed, isEmpty);
      expect(m.history, hasLength(2));
    });

    test('el aviso del socket manda sobre la ventana de la API del mismo caso',
        () async {
      page([
        json(id: 'p1', status: 'accepted', extra: {'caseStatus': 'confirmed'})
      ]);
      await m.load();
      board.handle(WindowConfirmed(ConfirmedWindow(
          caseId: 'c1',
          start: DateTime.utc(2026, 11, 6, 11),
          end: DateTime.utc(2026, 11, 6, 15),
          taskName: 'Service',
          patent: 'AB123CD',
          source: 'admin')));
      expect(m.confirmed, hasLength(1));
      expect(m.confirmed.single.start, DateTime.utc(2026, 11, 6, 11));
    });

    test('eventos: caso escalado avisa', () async {
      page([]);
      await m.load();
      m.init();
      board.handle(const CaseEscalated(caseId: 'c1', taskName: 'Service'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(m.notice, contains('pasó al administrador'));
    });

    test('eventos: una propuesta nueva se relee', () async {
      page([]);
      await m.load();
      m.init();
      page([json()]);
      board.handle(ProposalReceived(proposal()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(m.current, isNotNull);
    });
  });

  group('RejectProposalViewModel', () {
    late MockMaintenanceRepository repo;
    RejectProposalViewModel make({MaintenanceSettings? s = settings}) =>
        RejectProposalViewModel(
            proposal: proposal(), settings: s, repo: repo, now: () => today);

    setUp(() => repo = MockMaintenanceRepository());

    test('el motivo es obligatorio y tiene tope', () {
      final m = make();
      expect(m.canSubmit, isFalse);
      expect(m.blocker, 'Contanos por qué no podés.');
      m.setReason('   ');
      expect(m.canSubmit, isFalse);
      m.setReason('a' * 501);
      expect(m.blocker, 'Máximo 500 caracteres.');
      m.setReason('Tengo turno médico');
      expect(m.canSubmit, isTrue);
    });

    test('rechazo sin alternativa manda sólo el motivo', () async {
      when(repo.reject('p1',
              reason: anyNamed('reason'),
              altStart: anyNamed('altStart'),
              altEnd: anyNamed('altEnd')))
          .thenAnswer((_) async =>
              MaintenanceProposal.fromJson(json(status: 'rejected')));
      final m = make()..setReason('  Tengo turno médico ');
      await m.submit();
      verify(repo.reject('p1',
              reason: '  Tengo turno médico ', altStart: null, altEnd: null))
          .called(1);
      expect(m.result!.status, ProposalStatus.rejected);
      expect(m.failure, isNull);
    });

    test('con alternativa viable la manda en UTC', () async {
      when(repo.reject('p1',
              reason: anyNamed('reason'),
              altStart: anyNamed('altStart'),
              altEnd: anyNamed('altEnd')))
          .thenAnswer((_) async =>
              MaintenanceProposal.fromJson(json(status: 'rejected')));
      final m = make()
        ..setReason('No puedo')
        ..setWantsAlternative(true);
      expect(m.canSubmit, isFalse, reason: 'falta elegir la ventana');
      m
        ..setDay(DateTime(2026, 11, 5))
        ..setStart(9 * 60)
        ..setEnd(12 * 60);
      expect(m.alternativeError, isNull);
      await m.submit();
      verify(repo.reject('p1',
              reason: 'No puedo',
              altStart: DateTime.utc(2026, 11, 5, 12),
              altEnd: DateTime.utc(2026, 11, 5, 15)))
          .called(1);
      expect(m.result, isNotNull);
    });

    test('una alternativa inviable no se manda', () async {
      final m = make()
        ..setReason('No puedo')
        ..setWantsAlternative(true)
        ..setDay(DateTime(2026, 11, 8))
        ..setStart(9 * 60)
        ..setEnd(12 * 60);
      expect(m.canSubmit, isFalse);
      expect(m.alternativeError, startsWith('El taller no atiende'));
      await m.submit();
      verifyNever(repo.reject(any,
          reason: anyNamed('reason'),
          altStart: anyNamed('altStart'),
          altEnd: anyNamed('altEnd')));
    });

    test('el 400 del back (alternativa no viable) se muestra', () async {
      when(repo.reject('p1',
              reason: anyNamed('reason'),
              altStart: anyNamed('altStart'),
              altEnd: anyNamed('altEnd')))
          .thenThrow(fail(400, 'La zona quedaría sin cobertura ese día'));
      final m = make()
        ..setReason('No puedo')
        ..setWantsAlternative(true)
        ..setDay(DateTime(2026, 11, 5))
        ..setStart(9 * 60)
        ..setEnd(12 * 60);
      await m.submit();
      expect(m.failure, 'La zona quedaría sin cobertura ese día');
      expect(m.result, isNull);
      expect(m.isBusy, isFalse);
    });

    test('el 409 (ya no está vigente) se muestra', () async {
      when(repo.reject('p1',
              reason: anyNamed('reason'),
              altStart: anyNamed('altStart'),
              altEnd: anyNamed('altEnd')))
          .thenThrow(fail(409, 'La propuesta ya venció'));
      final m = make()..setReason('No puedo');
      await m.submit();
      expect(m.failure, 'La propuesta ya venció');
    });

    test('sin días elegibles se avisa y no se puede proponer', () {
      final m = RejectProposalViewModel(
          proposal: MaintenanceProposal.fromJson(json()),
          settings: const MaintenanceSettings(
              workshopStartHour: 8,
              workshopEndHour: 13,
              workshopDays: [],
              holidays: [],
              minLeadDays: 1,
              horizonDays: 30,
              proposalTtlHours: 24),
          repo: repo,
          now: () => today);
      expect(m.canPropose, isFalse);
      expect(m.cannotProposeReason, contains('No hay días del taller'));
      expect(m.dayBounds, isNull);
    });

    test('el selector abre en el primer día elegible y respeta el vencimiento',
        () {
      final m = RejectProposalViewModel(
          proposal: MaintenanceProposal.fromJson(
              json(extra: {'projectedDueAt': '2026-11-06T03:00:00.000Z'})),
          settings: settings,
          repo: repo,
          now: () => today);
      final (first, last, initial) = m.dayBounds!;
      expect(first, DateTime(2026, 11, 3));
      expect(last, DateTime(2026, 11, 5));
      expect(initial, first);
      expect(m.isSelectableDay(DateTime.utc(2026, 11, 9)), isFalse);
    });

    test('el 400 del back llega sin el prefijo técnico', () async {
      when(repo.reject('p1',
              reason: anyNamed('reason'),
              altStart: anyNamed('altStart'),
              altEnd: anyNamed('altEnd')))
          .thenThrow(fail(400,
              'alternative: ese día dejaría la zona de cobertura por debajo del mínimo'));
      final m = make()
        ..setReason('No puedo')
        ..setWantsAlternative(true)
        ..setDay(DateTime(2026, 11, 5))
        ..setStart(9 * 60)
        ..setEnd(12 * 60);
      await m.submit();
      expect(m.failure,
          'Ese día dejaría la zona de cobertura por debajo del mínimo');
    });

    test(
        'con la hoja abierta los avisos esperan, y si la propuesta se cierra la hoja lo sabe',
        () async {
      final board = MaintenanceBoard(now: () => today);
      final notifier = MockMaintenanceNotifier();
      final m = RejectProposalViewModel(
          proposal: proposal(),
          settings: settings,
          repo: repo,
          board: board,
          notifier: notifier,
          now: () => today)
        ..init();
      verify(notifier.sheetOpened()).called(1);
      board.handle(const ProposalClosed('otra', 'expired'));
      expect(m.closedByBack, isFalse);
      board.handle(const ProposalClosed('p1', 'expired'));
      await Future<void>.delayed(Duration.zero);
      expect(m.closedByBack, isTrue);
      m.dispose();
      verify(notifier.sheetClosed()).called(1);
    });

    test('sin el horario del taller no se puede proponer otra ventana', () {
      final m = make(s: null)..setWantsAlternative(true);
      expect(m.canPropose, isFalse);
      expect(m.wantsAlternative, isFalse);
    });
  });

  group('HttpMaintenanceRepository', () {
    late MockApiClient api;
    late MockDriverAuthService auth;
    late HttpMaintenanceRepository repo;

    setUp(() {
      api = MockApiClient();
      auth = MockDriverAuthService();
      when(auth.token).thenAnswer((_) async => 'tok');
      repo = HttpMaintenanceRepository(api: api, auth: auth);
    });

    Response res(Object data) => Response(
        requestOptions: RequestOptions(path: ''), data: data, statusCode: 200);

    test(
        'lista, horario y aceptar pegan a /api/v2/driver/maintenance-proposals',
        () async {
      when(api.get(
              argThat(contains(
                  '/api/v2/driver/maintenance-proposals?limit=50&offset=0')),
              'tok'))
          .thenAnswer((_) async => res({
                'data': [json()],
                'total': 1
              }));
      when(api.get(HttpMaintenanceRepository.settingsPath, 'tok'))
          .thenAnswer((_) async => res({
                'workshopStartHour': 8,
                'workshopEndHour': 13,
                'workshopDays': [1, 2],
                'holidays': [],
                'minLeadDays': 1,
                'horizonDays': 30,
                'proposalTtlHours': 24,
              }));
      when(api.post(HttpMaintenanceRepository.acceptPath('p1'), {}, 'tok', any))
          .thenAnswer((_) async => res(json(status: 'accepted')));
      final page = await repo.proposals();
      expect(page.total, 1);
      expect((await repo.settings()).workshopDays, [1, 2]);
      expect((await repo.accept('p1')).status, ProposalStatus.accepted);
      final sent = verify(api.post(HttpMaintenanceRepository.acceptPath('p1'),
              {}, 'tok', captureAny))
          .captured
          .single as Map<String, String>;
      expect(sent['Idempotency-Key'], isNotEmpty);
    });

    test('reset y otro chofer descartan la clave de idempotencia', () async {
      var user = 'u1';
      when(auth.userId).thenAnswer((_) => user);
      final keys = <String>[];
      when(api.post(any, any, any, any)).thenAnswer((i) async {
        keys.add((i.positionalArguments[3]
            as Map<String, String>)['Idempotency-Key']!);
        throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionError);
      });
      Future<void> tryAccept() async {
        try {
          await repo.accept('p1');
        } catch (_) {}
      }

      await tryAccept();
      await tryAccept();
      expect(keys[1], keys[0], reason: 'misma sesión: se reusa');
      repo.reset();
      await tryAccept();
      expect(keys[2], isNot(keys[0]));
      user = 'u2';
      await tryAccept();
      expect(keys[3], isNot(keys[2]), reason: 'otro chofer');
    });

    test('rechazar manda motivo y alternativa en ISO UTC', () async {
      when(api.post(any, any, any, any))
          .thenAnswer((_) async => res(json(status: 'rejected')));
      await repo.reject('p1',
          reason: ' No puedo ',
          altStart: DateTime.utc(2026, 11, 5, 12),
          altEnd: DateTime.utc(2026, 11, 5, 15));
      verify(api.post(
              HttpMaintenanceRepository.rejectPath('p1'),
              {
                'reason': 'No puedo',
                'alternative': {
                  'start': '2026-11-05T12:00:00.000Z',
                  'end': '2026-11-05T15:00:00.000Z',
                },
              },
              'tok',
              any))
          .called(1);
    });

    test(
        'con un rechazo de negocio la clave se descarta; sin respuesta se reusa',
        () async {
      final keys = <String>[];
      when(api.post(any, any, any, any)).thenAnswer((i) async {
        keys.add((i.positionalArguments[3]
            as Map<String, String>)['Idempotency-Key']!);
        throw keys.length < 3
            ? DioException(
                requestOptions: RequestOptions(path: ''),
                type: DioExceptionType.connectionError)
            : fail(409, 'ya');
      });
      for (var i = 0; i < 3; i++) {
        await expectLater(repo.accept('p1'), throwsA(isA<DioException>()));
      }
      expect(keys[0], keys[1],
          reason: 'sin respuesta se reintenta con la misma clave');
      await expectLater(repo.accept('p1'), throwsA(isA<DioException>()));
      expect(keys.last, isNot(keys[0]),
          reason: 'tras el 409 la clave se descartó');
    });
  });
}
