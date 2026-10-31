import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_repository.dart';

/// Qué eligió el chofer en el aviso de propuesta nueva.
enum NoticeAction { accept, reject, later }

/// Un aviso en pantalla, que se puede cerrar por su identidad (nunca "lo que
/// esté arriba").
abstract class NoticeHandle {
  /// La elección del chofer; null si se cerró desde afuera ([dismiss]).
  Future<NoticeAction?> get result;

  /// Cierra este aviso, esté donde esté en la pila.
  void dismiss();
}

/// Cómo se dibuja el aviso (la app usa una ruta propia; los tests, un doble).
abstract class NoticePresenter {
  NoticeHandle show(MaintenanceProposal proposal);
}

/// Dueño de los avisos del planificador de taller en el Inicio: decide cuándo
/// mostrar la propuesta nueva y cuándo esperar.
///
/// Regla de fondo: **nada del taller se pone encima de una oferta de pedido ni
/// de un pedido en curso.** La oferta de M1 se cierra con `completeDialog`
/// (saca la ruta de más arriba): cualquier pantalla ajena encima la traba.
/// - La oferta tiene prioridad: si llega con un aviso abierto, éste se cierra
///   por identidad, vuelve a la cola y reaparece cuando la oferta se resuelve.
/// - Con un pedido en curso o una oferta abierta, ni los avisos ni la
///   pantalla Taller (por un push tocado) se abren: la intención queda
///   guardada y se ejecuta cuando termina.
/// - Con la hoja "No puedo" abierta, los avisos nuevos esperan.
/// - Varias propuestas vigentes a la vez (una por tarea) se encolan en orden.
/// - Un aviso vence con su `expiresAt`, sin esperar al barrido del back.
class MaintenanceNotifier {
  MaintenanceNotifier({
    MaintenanceRepository? repo,
    MaintenanceBoard? board,
    NoticePresenter? presenter,
    DialogService? dialogs,
    Future<void> Function()? openTallerRoute,
    DateTime Function()? now,
  })  : _repo = repo,
        _board = board,
        _presenter = presenter,
        _dialogs = dialogs,
        _openTallerRoute = openTallerRoute,
        _now = now ?? DateTime.now;

  final MaintenanceRepository? _repo;
  final MaintenanceBoard? _board;
  NoticePresenter? _presenter;
  final DialogService? _dialogs;
  final Future<void> Function()? _openTallerRoute;
  final DateTime Function() _now;

  MaintenanceRepository get _repository =>
      _repo ?? locator<MaintenanceRepository>();
  MaintenanceBoard get _hub => _board ?? locator<MaintenanceBoard>();
  DialogService get _dialog => _dialogs ?? locator<DialogService>();
  NoticePresenter get _present => _presenter ??= presenterFactory!();

  /// Cómo se dibuja el aviso en la app real; lo fija `main` (el servicio no
  /// conoce la capa de vistas).
  static NoticePresenter Function()? presenterFactory;

  /// Lo fija el Inicio: hay un pedido en curso (flujo de entrega o cobro).
  bool Function()? isBusyWithOrder;

  final List<MaintenanceProposal> _queue = [];
  final List<({String title, String description})> _infos = [];

  /// Las que el chofer postergó con «Después»: no se le vuelven a mostrar solas
  /// (siguen en la marca del Inicio y en Taller). Las que se ocultaron por otra
  /// cosa (una oferta, quedar fuera de línea) no están acá y vuelven.
  final Set<String> _postponed = {};
  List<MaintenanceProposal> _pending = const [];
  StreamSubscription<MaintenanceEvent>? _sub;
  final _changes = StreamController<void>.broadcast();

  bool _running = false;
  bool _openTallerPending = false;
  int _offers = 0;
  int _sheets = 0;
  int _seq = 0;

  /// Generación de la sesión: una lectura que vuelve después de un [reset] se
  /// descarta.
  int _gen = 0;
  MaintenanceProposal? _shown;
  NoticeHandle? _handle;
  Timer? _expiry;

  /// Propuestas que esperan la respuesta del chofer (vigentes), para la marca
  /// del Inicio.
  List<MaintenanceProposal> get pending {
    final n = _now();
    return [
      for (final p in _pending)
        if (p.isOpen(n)) p,
    ];
  }

  /// Cambió [pending].
  Stream<void> get changes => _changes.stream;

  @visibleForTesting
  String? get shownProposalId => _shown?.proposalId;

  @visibleForTesting
  MaintenanceProposal? get shownProposal => _shown;

  @visibleForTesting
  List<String> get queuedIds => [for (final p in _queue) p.proposalId];

  /// Hay una oferta de pedido abierta o un pedido en curso: nada del taller
  /// se pone encima.
  bool get _busyWithOrder => _offers > 0 || (isBusyWithOrder?.call() ?? false);

  /// El chofer está en línea: escucha el socket y muestra los avisos.
  void start() {
    _running = true;
    _sub?.cancel();
    _sub = _hub.events.listen(_onEvent);
  }

  /// Fuera de línea: nada queda en pantalla ni en cola. Las cuentas de ofertas
  /// y hojas abiertas no se tocan (se cierran solas con su fin); lo postergado
  /// con «Después» se conserva.
  void stop() {
    _running = false;
    _sub?.cancel();
    _sub = null;
    _dismissShown();
    _queue.clear();
    _infos.clear();
  }

  /// Cierre de sesión: además se descarta lo pendiente de ese chofer.
  void reset() {
    stop();
    _gen++;
    _postponed.clear();
    _pending = const [];
    _openTallerPending = false;
    _changes.add(null);
  }

  /// Lee las propuestas vigentes del back (al abrir la app, al ponerse en
  /// línea y al volver a primer plano): alimenta la marca del Inicio y, en
  /// línea, muestra el aviso de las que el chofer todavía no postergó (la que
  /// dejó el planificador de la madrugada no puede pasar desapercibida).
  Future<void> sync() async {
    final gen = _gen;
    try {
      final page = await _repository.proposals();
      if (gen != _gen) return; // llegó después de un cierre de sesión
      final n = _now();
      _pending = [
        for (final p in page.proposals)
          if (p.isOpen(n)) p,
      ];
      _changes.add(null);
      if (_running) {
        for (final p in _pending) {
          _enqueue(p);
        }
        _pump();
      }
    } catch (e) {
      debugPrint('No se pudieron leer las propuestas de taller: $e');
    }
  }

  /// Algo que bloqueaba terminó (un pedido en curso): se reintenta lo que
  /// esperaba.
  void recheck() => _pump();

  void offerStarted() {
    _offers++;
    final shown = _shown;
    if (shown != null) {
      // Se cierra por identidad y vuelve al frente de la cola.
      _dismissShown();
      _queue.insert(0, shown);
    }
  }

  void offerEnded({bool pump = true}) {
    if (_offers > 0) _offers--;
    if (pump) _pump();
  }

  /// La hoja "No puedo" se abrió/cerró: mientras está abierta los avisos esperan.
  void sheetOpened() => _sheets++;

  void sheetClosed() {
    if (_sheets > 0) _sheets--;
    _pump();
  }

  /// Abre Taller sin apilar otra pantalla si ya está abierta (en ese caso la
  /// refresca). Con una oferta de pedido o un pedido en curso espera: se
  /// guarda la intención y se abre cuando terminan.
  Future<void> openTaller() async {
    if (_busyWithOrder) {
      _openTallerPending = true;
      return;
    }
    if (_hub.tallerOpen > 0) {
      _hub.notifyChanged();
      return;
    }
    await (_openTallerRoute?.call() ??
        locator<NavigationService>().navigateToTallerView());
  }

  /// Hubo un cambio local en las propuestas (aceptó una desde el aviso).
  void _changed(String proposalId) {
    _hub.notifyChanged(proposalId);
    unawaited(sync());
  }

  void _onEvent(MaintenanceEvent e) {
    switch (e) {
      case ProposalReceived(:final proposal):
        if (proposal.isOpen(_now())) {
          _pending = [
            ..._pending.where((p) => p.proposalId != proposal.proposalId),
            proposal,
          ];
          _changes.add(null);
        }
        _enqueue(proposal, fromEvent: true);
        _pump();
      case ProposalClosed(:final proposalId):
        _forget(proposalId);
        _pump();
      case ProposalsChanged(:final proposalId):
        // La app ya respondió esa propuesta (desde Taller): su aviso viejo
        // daría un 409.
        if (proposalId != null) {
          _forget(proposalId);
          _pump();
        }
      case WindowConfirmed(:final window):
        _info(
            'Taller confirmado',
            'El administrador confirmó el taller de ${window.vehicleLabel} '
                '(${window.taskName}): ${formatWindow(window.start, window.end)}. '
                'El despacho no te va a ofrecer pedidos en ese horario.');
      case CaseEscalated(:final taskName, :final vehicleLabel):
        _info(
            'El taller pasó al administrador',
            'No quedó una ventana para "$taskName" de $vehicleLabel. El '
                'administrador se va a comunicar con vos.');
    }
  }

  /// La propuesta ya no hay que avisarla (cerrada o respondida).
  void _forget(String proposalId) {
    _queue.removeWhere((p) => p.proposalId == proposalId);
    _pending = [
      for (final p in _pending)
        if (p.proposalId != proposalId) p,
    ];
    _changes.add(null);
    if (_shown?.proposalId == proposalId) _dismissShown();
  }

  /// Encola [p] salvo que ya esté en pantalla, en la cola o postergada. Con
  /// [fromEvent] una propuesta que el back reemite (mismo id, datos nuevos)
  /// actualiza lo que se muestra en vez de descartarse.
  void _enqueue(MaintenanceProposal p, {bool fromEvent = false}) {
    final id = p.proposalId;
    if (!p.isOpen(_now())) return;
    // Con Taller abierto la propuesta ya se ve ahí: no se apila un aviso encima.
    if (_hub.tallerOpen > 0) return;
    if (_shown?.proposalId == id) {
      if (fromEvent && !_same(_shown!, p)) {
        _dismissShown();
        _queue.insert(0, p);
      }
      return;
    }
    final i = _queue.indexWhere((q) => q.proposalId == id);
    if (i >= 0) {
      _queue[i] = p;
      return;
    }
    if (_postponed.contains(id)) {
      if (!fromEvent) return;
      _postponed.remove(id);
    }
    _queue.add(p);
  }

  static bool _same(MaintenanceProposal a, MaintenanceProposal b) =>
      a.windowStart == b.windowStart &&
      a.windowEnd == b.windowEnd &&
      a.expiresAt == b.expiresAt &&
      a.urgent == b.urgent &&
      a.taskName == b.taskName;

  void _info(String title, String description) {
    _infos.add((title: title, description: description));
    _pump();
  }

  void _dismissShown() {
    _expiry?.cancel();
    _expiry = null;
    _seq++;
    final h = _handle;
    _handle = null;
    _shown = null;
    h?.dismiss();
  }

  void _pump() {
    // La intención de abrir Taller (push tocado) espera a que termine la
    // oferta o el pedido; con la app fuera de línea igual se atiende.
    if (_openTallerPending && !_busyWithOrder) {
      _openTallerPending = false;
      unawaited(openTaller());
    }
    if (!_running || _busyWithOrder || _sheets > 0) return;
    // Los avisos informativos usan el diálogo común: nunca encima de una
    // oferta, un pedido en curso o un aviso abierto.
    if (_shown == null && _infos.isNotEmpty) {
      final i = _infos.removeAt(0);
      unawaited(_dialog
          .showDialog(title: i.title, description: i.description)
          .then((_) => _pump()));
      return;
    }
    if (_shown != null) return;
    final n = _now();
    _queue.removeWhere((p) => !p.isOpen(n));
    if (_queue.isEmpty) return;
    unawaited(_show(_queue.removeAt(0)));
  }

  Future<void> _show(MaintenanceProposal p) async {
    final seq = ++_seq;
    _shown = p;
    final handle = _present.show(p);
    _handle = handle;
    final left = p.expiresAt.difference(_now().toUtc());
    _expiry = Timer(left.isNegative ? Duration.zero : left, () {
      if (_seq != seq) return;
      _pending = [
        for (final x in _pending)
          if (x.proposalId != p.proposalId) x,
      ];
      _changes.add(null);
      _dismissShown();
      _pump();
    });
    final action = await handle.result;
    // Se cerró desde afuera (oferta, vencimiento, propuesta cerrada).
    if (_seq != seq) return;
    _expiry?.cancel();
    _expiry = null;
    _shown = null;
    _handle = null;
    switch (action) {
      case NoticeAction.accept:
        await _accept(p);
      case NoticeAction.reject:
        await openTaller();
      case NoticeAction.later:
        _postponed.add(p.proposalId);
      case null:
        break;
    }
    _pump();
  }

  Future<void> _accept(MaintenanceProposal p) async {
    try {
      await _repository.accept(p.proposalId);
      _changed(p.proposalId);
      _info(
          'Aceptaste el turno',
          'Queda a la espera de que el administrador lo confirme. Te '
              'avisamos cuando lo haga.');
    } catch (e) {
      _info('No pudimos aceptar el turno', maintenanceErrorText(e));
    }
  }

  void dispose() {
    stop();
    _changes.close();
  }
}

/// Texto de un fallo del back al responder una propuesta, sin el prefijo técnico
/// del campo (`alternative: …`).
String maintenanceErrorText(Object e) => cleanApiMessage(actionErrorText(e));
