// Ventanas de taller que el planificador le propone al chofer (CU-105, M2).
// Lecturas tolerantes: lo que falte queda en null o en un valor neutro.

import 'package:splg_driver/models/driver_data.dart';

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _date(Object? v) => DateTime.tryParse(_str(v) ?? '')?.toUtc();

/// Husos: el taller y los feriados son de la hora argentina (UTC-3, sin
/// horario de verano). Las ventanas viajan en UTC.
const Duration kArgentinaOffset = Duration(hours: 3);

/// El instante [d] con los campos (día, hora) de la hora argentina. Sólo para
/// leer o mostrar: el valor resultante es "UTC" por construcción.
DateTime asArgentina(DateTime d) => d.toUtc().subtract(kArgentinaOffset);

/// Día calendario argentino de [d] (a las 00:00, en "UTC").
DateTime argentinaDay(DateTime d) {
  final a = asArgentina(d);
  return DateTime.utc(a.year, a.month, a.day);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `14:30` en hora argentina.
String formatArTime(DateTime d) => formatTime(asArgentina(d));

/// `Martes 3 de noviembre` en hora argentina.
String formatArDay(DateTime d) => formatLongDate(asArgentina(d));

/// `Martes 3 de noviembre de 08:00 a 12:00`.
String formatWindow(DateTime start, DateTime end) =>
    '${formatArDay(start)} de ${formatArTime(start)} a ${formatArTime(end)}';

/// `YYYY-MM-DD` de un día calendario (año, mes y día de [d] tal cual).
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

enum ProposalStatus {
  pending('Esperando tu respuesta'),
  accepted('Aceptada'),
  rejected('Rechazada'),
  expired('Vencida'),
  cancelled('Cancelada');

  const ProposalStatus(this.label);

  final String label;

  static ProposalStatus parse(String? raw) => switch (raw) {
        'accepted' => accepted,
        'rejected' => rejected,
        'expired' => expired,
        'cancelled' => cancelled,
        _ => pending,
      };
}

/// Una propuesta de ventana de taller para el vehículo del chofer.
class MaintenanceProposal {
  const MaintenanceProposal({
    required this.proposalId,
    required this.taskName,
    required this.windowStart,
    required this.windowEnd,
    required this.expiresAt,
    this.caseId,
    this.taskId,
    this.carId,
    this.patent,
    this.rank,
    this.status = ProposalStatus.pending,
    this.respondedAt,
    this.rejectionReason,
    this.altWindowStart,
    this.altWindowEnd,
    this.urgent = false,
    this.caseStatus,
    this.projectedDueAt,
    this.confirmedStart,
    this.confirmedEnd,
  });

  final String proposalId;
  final String? caseId;
  final String? taskId;
  final String? carId;
  final String? patent;
  final String taskName;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime expiresAt;
  final int? rank;
  final ProposalStatus status;
  final DateTime? respondedAt;
  final String? rejectionReason;
  final DateTime? altWindowStart;
  final DateTime? altWindowEnd;
  final bool urgent;

  /// Estado del caso de planificación: `negotiating`, `awaiting_confirmation`,
  /// `escalated`, `confirmed` (el administrador confirmó la ventana) o
  /// `cancelled`; null si el back no lo informa.
  final String? caseStatus;

  /// Vencimiento proyectado de la tarea: una ventana que termina después es urgente.
  final DateTime? projectedDueAt;

  /// La ventana que confirmó el administrador (la aceptada, la alternativa del
  /// chofer u otra que fijó él); null si el caso no está confirmado.
  final DateTime? confirmedStart;
  final DateTime? confirmedEnd;

  bool get caseConfirmed => caseStatus == 'confirmed';

  /// Aceptada, o rechazada con otra ventana, y el caso sigue vivo sin
  /// confirmar: espera al administrador.
  bool isWaitingAdmin(DateTime now) =>
      (status == ProposalStatus.accepted || hasAlternative) &&
      !isPast(now) &&
      (caseStatus == null ||
          caseStatus == 'negotiating' ||
          caseStatus == 'awaiting_confirmation');

  /// La ventana confirmada del caso (con cualquier propuesta del caso, también
  /// si el administrador confirmó un caso escalado); null si no hay o ya pasó.
  ConfirmedWindow? confirmedWindow(DateTime now) {
    final start = confirmedStart, end = confirmedEnd, id = caseId;
    if (!caseConfirmed || start == null || end == null || id == null) {
      return null;
    }
    if (!now.toUtc().isBefore(end)) return null;
    return ConfirmedWindow(
      caseId: id,
      taskId: taskId,
      start: start,
      end: end,
      taskName: taskName,
      patent: patent,
    );
  }

  /// Espera la respuesta del chofer y todavía está a tiempo.
  bool isOpen(DateTime now) =>
      status == ProposalStatus.pending && now.toUtc().isBefore(expiresAt);

  /// Estaba esperando respuesta pero pasó su vencimiento (el back deriva el
  /// estado "vencida" de la fecha).
  bool isLapsed(DateTime now) =>
      status == ProposalStatus.expired ||
      (status == ProposalStatus.pending && !now.toUtc().isBefore(expiresAt));

  /// Rechazada con otra ventana propuesta por el chofer.
  bool get hasAlternative =>
      status == ProposalStatus.rejected &&
      altWindowStart != null &&
      altWindowEnd != null;

  /// La ventana cuyo turno ya pasó.
  bool isPast(DateTime now) => !now.toUtc().isBefore(windowEnd);

  String get vehicleLabel => patent ?? 'tu vehículo';

  MaintenanceProposal copyWith({ProposalStatus? status}) => MaintenanceProposal(
        caseStatus: caseStatus,
        projectedDueAt: projectedDueAt,
        confirmedStart: confirmedStart,
        confirmedEnd: confirmedEnd,
        proposalId: proposalId,
        caseId: caseId,
        taskId: taskId,
        carId: carId,
        patent: patent,
        taskName: taskName,
        windowStart: windowStart,
        windowEnd: windowEnd,
        expiresAt: expiresAt,
        rank: rank,
        status: status ?? this.status,
        respondedAt: respondedAt,
        rejectionReason: rejectionReason,
        altWindowStart: altWindowStart,
        altWindowEnd: altWindowEnd,
        urgent: urgent,
      );

  /// Respuesta de `GET /driver/maintenance-proposals` y de aceptar/rechazar;
  /// también el payload del socket `maintenance:proposal`, que trae menos campos.
  factory MaintenanceProposal.fromJson(Map<String, dynamic> json) {
    final start = _date(json['windowStart']) ?? DateTime.utc(1970);
    return MaintenanceProposal(
      proposalId: _str(json['proposalId']) ?? '',
      caseId: _str(json['caseId']),
      taskId: _str(json['taskId']),
      carId: _str(json['carId']),
      patent: _str(json['patent']),
      taskName: _str(json['taskName']) ?? 'Mantenimiento',
      windowStart: start,
      windowEnd: _date(json['windowEnd']) ?? start,
      expiresAt: _date(json['expiresAt']) ?? start,
      rank: json['rank'] is num ? (json['rank'] as num).toInt() : null,
      status: ProposalStatus.parse(_str(json['status'])),
      respondedAt: _date(json['respondedAt']),
      rejectionReason: _str(json['rejectionReason']),
      altWindowStart: _date(json['altWindowStart']),
      altWindowEnd: _date(json['altWindowEnd']),
      urgent: json['urgent'] == true,
      caseStatus: _str(json['caseStatus']),
      projectedDueAt: _date(json['projectedDueAt']),
      confirmedStart: _date(json['confirmedStart']),
      confirmedEnd: _date(json['confirmedEnd']),
    );
  }
}

class MaintenancePage {
  const MaintenancePage({this.proposals = const [], this.total = 0});

  final List<MaintenanceProposal> proposals;
  final int total;

  factory MaintenancePage.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return MaintenancePage(
      proposals: [
        if (data is List)
          for (final m in data.whereType<Map>())
            MaintenanceProposal.fromJson(Map<String, dynamic>.from(m)),
      ],
      total: json['total'] is num ? (json['total'] as num).toInt() : 0,
    );
  }
}

/// Ventana de taller que el administrador confirmó
/// (`maintenance:window-confirmed`): la agenda del vehículo quedó bloqueada.
class ConfirmedWindow {
  const ConfirmedWindow({
    required this.caseId,
    required this.start,
    required this.end,
    required this.taskName,
    this.taskId,
    this.patent,
    this.source,
  });

  final String caseId;
  final String? taskId;
  final DateTime start;
  final DateTime end;
  final String taskName;
  final String? patent;

  /// De dónde salió la ventana: `driver_accepted`, `driver_alternative` o `admin`.
  final String? source;

  String get vehicleLabel => patent ?? 'tu vehículo';

  factory ConfirmedWindow.fromJson(Map<String, dynamic> json) {
    final start = _date(json['windowStart']) ?? DateTime.utc(1970);
    return ConfirmedWindow(
      caseId: _str(json['caseId']) ?? '',
      taskId: _str(json['taskId']),
      start: start,
      end: _date(json['windowEnd']) ?? start,
      taskName: _str(json['taskName']) ?? 'Mantenimiento',
      patent: _str(json['patent']),
      source: _str(json['source']),
    );
  }
}

/// Lo que el back avisa del planificador por socket.
sealed class MaintenanceEvent {
  const MaintenanceEvent();
}

class ProposalReceived extends MaintenanceEvent {
  const ProposalReceived(this.proposal);

  final MaintenanceProposal proposal;
}

/// La propuesta dejó de correr: `expired`, `cancelled` o `resolved`.
class ProposalClosed extends MaintenanceEvent {
  const ProposalClosed(this.proposalId, this.reason);

  final String proposalId;
  final String? reason;
}

class WindowConfirmed extends MaintenanceEvent {
  const WindowConfirmed(this.window);

  final ConfirmedWindow window;
}

/// Algo cambió en las propuestas del chofer (la app respondió una): quien
/// muestra la lista se relee. No viene del back.
class ProposalsChanged extends MaintenanceEvent {
  const ProposalsChanged([this.proposalId]);

  /// La propuesta que respondió la app, si fue una (su aviso ya no sirve).
  final String? proposalId;
}

class CaseEscalated extends MaintenanceEvent {
  const CaseEscalated({
    required this.caseId,
    required this.taskName,
    this.taskId,
    this.patent,
    this.reason,
  });

  final String caseId;
  final String? taskId;
  final String taskName;
  final String? patent;
  final String? reason;

  String get vehicleLabel => patent ?? 'tu vehículo';
}

/// Horario del taller y límites para la ventana que el chofer propone
/// (`GET /driver/maintenance-proposals/settings`).
class MaintenanceSettings {
  const MaintenanceSettings({
    required this.workshopStartHour,
    required this.workshopEndHour,
    required this.workshopDays,
    required this.holidays,
    required this.minLeadDays,
    required this.horizonDays,
    required this.proposalTtlHours,
  });

  final int workshopStartHour;
  final int workshopEndHour;

  /// 0 = domingo … 6 = sábado.
  final List<int> workshopDays;

  /// `YYYY-MM-DD` de los feriados en los que el taller no atiende.
  final List<String> holidays;
  final int minLeadDays;
  final int horizonDays;
  final int proposalTtlHours;

  factory MaintenanceSettings.fromJson(Map<String, dynamic> json) {
    int n(String k, int d) => json[k] is num ? (json[k] as num).toInt() : d;
    List<T> list<T>(String k, T? Function(Object?) f) {
      final v = json[k];
      return v is List
          ? [
              for (final e in v)
                if (f(e) != null) f(e) as T,
            ]
          : <T>[];
    }

    return MaintenanceSettings(
      workshopStartHour: n('workshopStartHour', 8),
      workshopEndHour: n('workshopEndHour', 13),
      workshopDays:
          list<int>('workshopDays', (e) => e is num ? e.toInt() : null),
      holidays: list<String>('holidays', (e) => _str(e)),
      minLeadDays: n('minLeadDays', 0),
      horizonDays: n('horizonDays', 30),
      proposalTtlHours: n('proposalTtlHours', 24),
    );
  }

  /// `Lunes a sábado, de 8:00 a 13:00`-style: los días y el horario en una línea.
  String get scheduleText {
    const names = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
    final days = [...workshopDays]..sort();
    final list =
        days.isEmpty ? 'sin días' : days.map((d) => names[d % 7]).join(', ');
    return '$list, de ${_two(workshopStartHour)}:00 a ${_two(workshopEndHour)}:00';
  }

  /// Los días argentinos (a las 00:00 "UTC") en que se puede proponer una
  /// ventana: hábiles, no feriados, entre el aviso mínimo y el horizonte, y
  /// anteriores al día del vencimiento proyectado [due]. Si ninguno llega a
  /// tiempo (tarea vencida o por vencer) se admiten todos, como hace el back.
  List<DateTime> selectableDays(DateTime now, {DateTime? due}) {
    final today = argentinaDay(now);
    final all = <DateTime>[];
    for (var i = minLeadDays; i <= horizonDays; i++) {
      final d = today.add(Duration(days: i));
      if (workshopDays.contains(d.weekday % 7) &&
          !holidays.contains(dayKey(d))) {
        all.add(d);
      }
    }
    if (due == null) return all;
    final dueDay = argentinaDay(due);
    final inTime = all.where((d) => d.isBefore(dueDay)).toList();
    return inTime.isNotEmpty ? inTime : all;
  }

  bool isSelectableDay(DateTime day, DateTime now, {DateTime? due}) {
    final d = DateTime.utc(day.year, day.month, day.day);
    return selectableDays(now, due: due).contains(d);
  }

  /// Por qué la ventana `day` `startMinutes`–`endMinutes` (minutos desde las
  /// 00:00, hora argentina) no sirve; null si es viable para la app. El back
  /// vuelve a validarla (cobertura de la zona).
  String? validateAlternative(
      DateTime? day, int? startMinutes, int? endMinutes, DateTime now,
      {DateTime? due}) {
    if (day == null) return 'Elegí el día.';
    if (startMinutes == null || endMinutes == null) {
      return 'Elegí el horario de inicio y de fin.';
    }
    final d = DateTime.utc(day.year, day.month, day.day);
    final today = argentinaDay(now);
    final offset = d.difference(today).inDays;
    if (!workshopDays.contains(d.weekday % 7)) {
      return 'El taller no atiende ese día. Atiende: $scheduleText.';
    }
    if (holidays.contains(dayKey(d))) return 'Ese día es feriado.';
    if (offset < minLeadDays) {
      return minLeadDays <= 1
          ? 'Necesitamos al menos un día de aviso.'
          : 'Necesitamos al menos $minLeadDays días de aviso.';
    }
    if (offset > horizonDays) {
      return 'Elegí una fecha dentro de los próximos $horizonDays días.';
    }
    if (!isSelectableDay(d, now, due: due)) {
      return 'Elegí un día anterior al vencimiento de la tarea.';
    }
    if (endMinutes <= startMinutes) {
      return 'El fin tiene que ser después del inicio.';
    }
    if (startMinutes < workshopStartHour * 60 ||
        endMinutes > workshopEndHour * 60) {
      return 'Elegí un horario entre las ${_two(workshopStartHour)}:00 y las '
          '${_two(workshopEndHour)}:00, que es cuando atiende el taller.';
    }
    if (!toUtc(d, startMinutes).isAfter(now.toUtc())) {
      return 'Esa hora ya pasó.';
    }
    return null;
  }

  /// El instante UTC de `day` a las `minutes` minutos de hora argentina.
  static DateTime toUtc(DateTime day, int minutes) =>
      DateTime.utc(day.year, day.month, day.day)
          .add(Duration(minutes: minutes))
          .add(kArgentinaOffset);
}

/// Los mensajes del back de los campos llegan con un prefijo técnico
/// (`alternative: el día tiene que…`, `reason: indicá el motivo`): se muestra
/// sólo la parte legible, con la primera letra en mayúscula.
String cleanApiMessage(String message) {
  final m = RegExp(r'^[A-Za-z_][\w.\[\]]*:\s+(.+)$', dotAll: true)
      .firstMatch(message.trim());
  final text = m == null ? message.trim() : m.group(1)!;
  return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}
