import 'dart:async';

import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'package:splg_driver/services/maintenance_repository.dart';

/// "No puedo": motivo obligatorio y, si quiere, otra ventana (un día y un
/// horario del taller). La app valida con las reglas del back; si igual el
/// back la rechaza (400), el motivo se muestra.
class RejectProposalViewModel extends BaseViewModel {
  RejectProposalViewModel({
    required this.proposal,
    required this.settings,
    MaintenanceRepository? repo,
    MaintenanceBoard? board,
    MaintenanceNotifier? notifier,
    DateTime Function()? now,
  })  : _repo = repo ?? locator<MaintenanceRepository>(),
        _boardOverride = board,
        _notifierOverride = notifier,
        now = now ?? DateTime.now;

  static const maxReason = 500;

  final MaintenanceProposal proposal;

  /// Horario del taller; null si no se pudo leer (no se puede proponer otra).
  final MaintenanceSettings? settings;
  final MaintenanceRepository _repo;
  final MaintenanceBoard? _boardOverride;
  final MaintenanceNotifier? _notifierOverride;
  MaintenanceBoard get _board => _boardOverride ?? locator<MaintenanceBoard>();
  MaintenanceNotifier get _notifier =>
      _notifierOverride ?? locator<MaintenanceNotifier>();
  DateTime Function() now;

  String reason = '';
  bool wantsAlternative = false;
  DateTime? day;
  int? startMinutes;
  int? endMinutes;

  String? failure;

  /// La propuesta ya resuelta, tras el rechazo.
  MaintenanceProposal? result;

  StreamSubscription<MaintenanceEvent>? _sub;
  bool _opened = false;

  /// La propuesta se cerró (venció, se canceló) con la hoja abierta: la vista
  /// se cierra sola.
  bool closedByBack = false;

  /// Mientras la hoja está abierta, los avisos nuevos esperan.
  void init() {
    if (_opened) return;
    _opened = true;
    _notifier.sheetOpened();
    _sub = _board.events.listen((e) {
      if (e is ProposalClosed && e.proposalId == proposal.proposalId) {
        closedByBack = true;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_opened) _notifier.sheetClosed();
    super.dispose();
  }

  bool get canPropose => settings != null && selectableDays.isNotEmpty;

  /// Los días en que se puede proponer una ventana (ver
  /// [MaintenanceSettings.selectableDays]).
  List<DateTime> get selectableDays =>
      settings?.selectableDays(now(), due: proposal.projectedDueAt) ?? const [];

  /// Por qué no se puede proponer otra ventana; null si se puede.
  String? get cannotProposeReason => settings == null
      ? 'No pudimos leer el horario del taller, así que por ahora no podés '
          'proponer otra ventana.'
      : selectableDays.isEmpty
          ? 'No hay días del taller disponibles antes del vencimiento, así '
              'que no podés proponer otra ventana. Te vamos a ofrecer la '
              'siguiente.'
          : null;

  /// Límites del selector de día: [first, last] y el día con que abre.
  (DateTime, DateTime, DateTime)? get dayBounds {
    final days = selectableDays;
    if (days.isEmpty) return null;
    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    return (local(days.first), local(days.last), local(days.first));
  }

  void setReason(String v) {
    reason = v;
    failure = null;
    notifyListeners();
  }

  void setWantsAlternative(bool v) {
    wantsAlternative = v && canPropose;
    failure = null;
    notifyListeners();
  }

  void setDay(DateTime? d) {
    day = d == null ? null : DateTime.utc(d.year, d.month, d.day);
    failure = null;
    notifyListeners();
  }

  void setStart(int minutes) {
    startMinutes = minutes;
    failure = null;
    notifyListeners();
  }

  void setEnd(int minutes) {
    endMinutes = minutes;
    failure = null;
    notifyListeners();
  }

  bool isSelectableDay(DateTime d) =>
      settings?.isSelectableDay(d, now(), due: proposal.projectedDueAt) ??
      false;

  String? get reasonError {
    final r = reason.trim();
    if (r.isEmpty) return 'Contanos por qué no podés.';
    if (r.length > maxReason) return 'Máximo $maxReason caracteres.';
    return null;
  }

  /// Qué le falta o qué está mal de la ventana alternativa; null si no la pide
  /// o si es viable.
  String? get alternativeError => !wantsAlternative
      ? null
      : settings!.validateAlternative(day, startMinutes, endMinutes, now(),
          due: proposal.projectedDueAt);

  String? get blocker => reasonError ?? alternativeError;

  bool get canSubmit => !isBusy && blocker == null;

  Future<void> submit() async {
    if (!canSubmit) return;
    failure = null;
    setBusy(true);
    try {
      final alt = wantsAlternative;
      result = await _repo.reject(
        proposal.proposalId,
        reason: reason,
        altStart: alt ? MaintenanceSettings.toUtc(day!, startMinutes!) : null,
        altEnd: alt ? MaintenanceSettings.toUtc(day!, endMinutes!) : null,
      );
    } catch (e) {
      failure = maintenanceErrorText(e);
    }
    setBusy(false);
  }
}
