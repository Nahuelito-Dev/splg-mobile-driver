import 'dart:async';

import 'package:splg_driver/models/maintenance.dart';

/// Punto único de los avisos del planificador de taller: recibe los eventos
/// (socket o push), recuerda las ventanas confirmadas y las reparte a quien
/// escuche (el Inicio avisa; la pantalla "Taller" se actualiza). Primero
/// actualiza su estado y recién después emite, así quien escucha lo ve al día.
///
/// El back no expone en la lista qué ventanas confirmó el administrador, así que
/// las confirmadas se conocen por el aviso y sólo durante la sesión de la app.
class MaintenanceBoard {
  MaintenanceBoard({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _events = StreamController<MaintenanceEvent>.broadcast();
  final List<ConfirmedWindow> _confirmed = [];
  StreamSubscription<MaintenanceEvent>? _source;

  Stream<MaintenanceEvent> get events => _events.stream;

  String? _owner;

  /// Cuántas pantallas "Taller" hay abiertas (para no apilar otra encima).
  int tallerOpen = 0;

  /// Ata el tablero al chofer de la sesión: si cambió, lo del anterior se
  /// descarta (nada de un chofer visible para otro).
  void bind(String? userId) {
    if (_owner != userId) reset();
    _owner = userId;
  }

  /// Cierre de sesión o cambio de chofer.
  void reset() {
    detach();
    _confirmed.clear();
    _owner = null;
  }

  /// La app cambió algo de sus propuestas (aceptó una): quien las lista se relee.
  void notifyChanged([String? proposalId]) =>
      _events.add(ProposalsChanged(proposalId));

  /// Confirmadas cuyo turno todavía no pasó, de la más próxima a la más lejana.
  List<ConfirmedWindow> get confirmed {
    final now = _now().toUtc();
    final list = _confirmed.where((w) => w.end.isAfter(now)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  /// Engancha la fuente de eventos (el socket) y suelta la anterior.
  void attach(Stream<MaintenanceEvent> source) {
    _source?.cancel();
    _source = source.listen(handle);
  }

  void detach() {
    _source?.cancel();
    _source = null;
  }

  void handle(MaintenanceEvent e) {
    if (e is WindowConfirmed) {
      _confirmed
        ..removeWhere((w) => w.caseId == e.window.caseId)
        ..add(e.window);
    } else if (e is CaseEscalated) {
      _confirmed.removeWhere((w) => w.caseId == e.caseId);
    }
    _events.add(e);
  }

  void dispose() {
    detach();
    _events.close();
  }
}
