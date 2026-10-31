import 'dart:async';

import 'package:dio/dio.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'package:splg_driver/services/maintenance_repository.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

/// "Taller": las ventanas que el planificador propone para el vehículo del
/// chofer (con cuenta regresiva; puede haber varias a la vez, una por tarea),
/// lo que espera al administrador, la ventana confirmada y el historial.
class TallerViewModel extends LoadViewModel {
  TallerViewModel({
    MaintenanceRepository? repo,
    MaintenanceBoard? board,
    DateTime Function()? now,
  })  : _repo = repo ?? locator<MaintenanceRepository>(),
        _board = board ?? locator<MaintenanceBoard>(),
        now = now ?? DateTime.now;

  final MaintenanceRepository _repo;
  final MaintenanceBoard _board;

  /// Propuestas por pedido al leer: la lista se pide completa (en varias
  /// páginas si hace falta) para que las vigentes, las que esperan y las
  /// confirmadas nunca queden fuera.
  static const pageSize = 50;
  static const maxPages = 20;

  /// Reloj inyectable para los tests.
  DateTime Function() now;

  List<MaintenanceProposal> _all = const [];
  MaintenanceSettings? settings;

  /// Por qué no se pudo leer el horario del taller (sin él no se propone otra
  /// ventana); null si se leyó.
  String? settingsError;

  /// Falla de la última acción (aceptar), para mostrar bajo la tarjeta.
  String? failure;

  /// Aviso informativo ("el administrador confirmó…").
  String? notice;

  String? busyProposalId;

  /// La propuesta a la que corresponde [failure].
  String? failedProposalId;
  StreamSubscription<MaintenanceEvent>? _sub;
  Timer? _ticker;
  bool _registered = false;

  void init() {
    if (!_registered) {
      _registered = true;
      _board.tallerOpen++;
    }
    _sub ??= _board.events.listen(_onEvent);
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  Future<void> fetch() async {
    final all = <MaintenanceProposal>[];
    for (var page = 0; page < maxPages; page++) {
      final r = await _repo.proposals(limit: pageSize, offset: all.length);
      all.addAll(r.proposals);
      if (r.proposals.isEmpty || all.length >= r.total) break;
    }
    _all = all;
    try {
      settings = await _repo.settings();
      settingsError = null;
    } catch (e) {
      settings = null;
      settingsError = maintenanceErrorText(e);
    }
  }

  /// Relee sin tapar la pantalla con el cargando (un aviso, un vencimiento).
  Future<void> refresh() async {
    try {
      await fetch();
      loadError = null;
    } catch (_) {
      // Se queda con lo que tenía; "Reintentar" aparece sólo en la carga inicial.
    }
    notifyListeners();
  }

  /// Las que esperan la respuesta del chofer, la que vence antes primero.
  List<MaintenanceProposal> get open {
    final n = now();
    return [
      for (final p in _all)
        if (p.isOpen(n)) p,
    ]..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  }

  /// Ventanas confirmadas por el administrador: las que informa la API (el
  /// caso en `confirmed`, con la ventana que quedó confirmada; sobreviven a un
  /// reinicio) y las avisadas por socket; ante el mismo caso manda el aviso.
  List<ConfirmedWindow> get confirmed {
    final n = now();
    final byCase = <String, ConfirmedWindow>{
      for (final p in _all)
        if (p.confirmedWindow(n) case final w?) w.caseId: w,
      for (final w in _board.confirmed) w.caseId: w,
    };
    return byCase.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Aceptadas (o con otra ventana propuesta) que esperan al administrador.
  List<MaintenanceProposal> get waiting {
    final n = now();
    final done = confirmed.map((w) => w.caseId).toSet();
    return [
      for (final p in _all)
        if (p.isWaitingAdmin(n) && !done.contains(p.caseId)) p,
    ];
  }

  /// El resto, de la más nueva a la más vieja.
  List<MaintenanceProposal> get history {
    final n = now();
    final done = confirmed.map((w) => w.caseId).toSet();
    final skip = {
      ...open.map((p) => p.proposalId),
      ...waiting.map((p) => p.proposalId),
    };
    return [
      for (final p in _all)
        if (!skip.contains(p.proposalId) &&
            !((p.status == ProposalStatus.accepted || p.hasAlternative) &&
                done.contains(p.caseId) &&
                !p.isPast(n)))
          p,
    ]..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
  }

  /// Cómo se rotula una propuesta del historial (la "vigente" que venció figura
  /// como vencida).
  String statusLabel(MaintenanceProposal p) =>
      p.isLapsed(now()) ? ProposalStatus.expired.label : p.status.label;

  bool get isEmpty =>
      open.isEmpty && waiting.isEmpty && confirmed.isEmpty && history.isEmpty;

  /// Segundos que le quedan a [p] para responder (0 si venció).
  int secondsLeft(MaintenanceProposal p) {
    final s = p.expiresAt.difference(now().toUtc()).inSeconds;
    return s < 0 ? 0 : s;
  }

  /// Marca "Urgente": sólo mientras la propuesta espera la respuesta.
  bool isUrgent(MaintenanceProposal p) => p.urgent && p.isOpen(now());

  Future<void> accept(MaintenanceProposal p) async {
    if (busyProposalId != null) return;
    failure = null;
    notice = null;
    busyProposalId = p.proposalId;
    notifyListeners();
    try {
      await _repo.accept(p.proposalId);
      _board.notifyChanged(p.proposalId);
      notice = 'Aceptaste el turno. Queda a la espera de que el administrador '
          'lo confirme.';
      await refresh();
    } catch (e) {
      failure = maintenanceErrorText(e);
      failedProposalId = p.proposalId;
      if (e is DioException && e.response?.statusCode == 409) {
        await refresh();
      }
    }
    busyProposalId = null;
    notifyListeners();
  }

  /// La hoja de "No puedo" respondió: la propuesta ya cambió de estado.
  void onRejected(MaintenanceProposal done) {
    _board.notifyChanged(done.proposalId);
    _all = [
      for (final x in _all) x.proposalId == done.proposalId ? done : x,
    ];
    failure = null;
    notice = done.hasAlternative
        ? 'Registramos tu propuesta de otra ventana. Queda a la espera del '
            'administrador.'
        : 'Registramos tu rechazo. Si hay otra ventana, te la vamos a '
            'proponer.';
    notifyListeners();
    unawaited(refresh());
  }

  void _onEvent(MaintenanceEvent e) {
    switch (e) {
      case ProposalReceived():
        notice = 'Tenés una propuesta de taller nueva.';
        unawaited(refresh());
      case ProposalClosed(:final proposalId, :final reason):
        _all = [
          for (final p in _all)
            if (p.proposalId == proposalId &&
                p.status == ProposalStatus.pending)
              p.copyWith(
                  status: reason == 'expired'
                      ? ProposalStatus.expired
                      : ProposalStatus.cancelled)
            else
              p,
        ];
        notifyListeners();
        unawaited(refresh());
      case WindowConfirmed(:final window):
        notice =
            'El administrador confirmó el taller de ${window.vehicleLabel}: '
            '${formatWindow(window.start, window.end)}. El despacho no te va '
            'a ofrecer pedidos en ese horario.';
        unawaited(refresh());
      case CaseEscalated(:final taskName):
        notice = 'El caso de "$taskName" pasó al administrador, que se va a '
            'comunicar con vos.';
        unawaited(refresh());
      case ProposalsChanged():
        unawaited(refresh());
    }
  }

  var _lapsedHandled = false;

  void _tick() {
    final live = _all.any((p) => p.status == ProposalStatus.pending);
    if (!live) return;
    if (open.length ==
        _all.where((p) => p.status == ProposalStatus.pending).length) {
      _lapsedHandled = false;
    } else if (!_lapsedHandled) {
      // Venció mientras miraba la pantalla: la lista se relee una vez.
      _lapsedHandled = true;
      unawaited(refresh());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_registered) _board.tallerOpen--;
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
