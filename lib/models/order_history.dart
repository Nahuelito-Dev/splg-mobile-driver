// Lo que el chofer ve en el detalle de una entrega además del pedido: las
// incidencias (`GET /incidents/order/:orderId`) y el historial de estados
// (`GET /orders/:id/status-history`). Tolerantes: lo que falte queda en null.
import 'package:splg_driver/models/driver_data.dart';

String? _s(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _date(Object? v) => DateTime.tryParse(_s(v) ?? '')?.toLocal();

/// Estado de una incidencia (`open`, `resolved`, `discarded`).
enum IncidentStatus {
  open('Abierta'),
  resolved('Resuelta'),
  discarded('Descartada');

  const IncidentStatus(this.label);
  final String label;

  static IncidentStatus parse(String? raw) => switch (raw) {
        'resolved' => resolved,
        'discarded' => discarded,
        _ => open,
      };
}

/// Una incidencia del pedido (`IncidentResponseDto`).
class OrderIncident {
  const OrderIncident({
    required this.id,
    required this.type,
    required this.description,
    required this.status,
    this.resolutionNote,
    this.createdAt,
    this.resolvedAt,
  });

  final String id;

  /// `damaged`, `out_of_stock`, `no_show`, `unpaid_collection` u `other`.
  final String type;
  final String description;
  final IncidentStatus status;

  /// Nota de quien la resolvió o la descartó.
  final String? resolutionNote;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  String get typeLabel => switch (type) {
        'damaged' => 'Garrafa dañada',
        'out_of_stock' => 'Sin stock para entregar',
        'no_show' => 'El cliente no estaba',
        'unpaid_collection' => 'Cobro impago',
        _ => 'Otro problema',
      };

  factory OrderIncident.fromJson(Map<String, dynamic> json) => OrderIncident(
        id: _s(json['incident_id']) ?? '',
        type: _s(json['type']) ?? 'other',
        description: _s(json['description']) ?? '',
        status: IncidentStatus.parse(_s(json['status'])),
        resolutionNote: _s(json['resolution_note']),
        createdAt: _date(json['createdAt']),
        resolvedAt: _date(json['resolvedAt']),
      );
}

/// Una fila del historial (`OrderStatusHistoryEntryDto`): un cambio de estado
/// o, con [isNote], una anotación (cobro manual, reasignación de chofer).
class StatusChange {
  const StatusChange({
    required this.toStatus,
    required this.isNote,
    this.fromStatus,
    this.reason,
    this.changedAt,
    this.actorRole,
  });

  /// null en el alta del pedido.
  final DriverOrderStatus? fromStatus;
  final DriverOrderStatus toStatus;
  final bool isNote;
  final String? reason;
  final DateTime? changedAt;

  /// `customer`, `delivery`, `admin` o `super_admin`; null si lo hizo el
  /// sistema o la cuenta ya no está.
  final String? actorRole;

  String get actorLabel => switch (actorRole) {
        'customer' => 'Cliente',
        'delivery' => 'Chofer',
        'admin' || 'super_admin' => 'Distribuidora',
        _ => 'Sistema',
      };

  /// "Pendiente", "Pendiente → Aceptado" o, si es una anotación, "Nota".
  String get title {
    if (isNote) return 'Nota';
    final from = fromStatus;
    return from == null ? toStatus.label : '${from.label} → ${toStatus.label}';
  }

  factory StatusChange.fromJson(Map<String, dynamic> json) {
    final from = _s(json['fromStatus']);
    final by = json['changedBy'];
    return StatusChange(
      fromStatus: from == null ? null : DriverOrderStatus.parse(from),
      toStatus: DriverOrderStatus.parse(_s(json['toStatus'])),
      isNote: json['isNote'] == true,
      reason: _s(json['reason']),
      changedAt: _date(json['changedAt']),
      actorRole: by is Map ? _s(by['role']) : null,
    );
  }
}
