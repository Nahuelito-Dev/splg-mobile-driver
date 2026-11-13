// Recorridos ofrecidos al chofer (CU-107, M4, API v2): un lote de pedidos
// cercanos, en el orden en que conviene entregarlos. Lecturas tolerantes: lo que
// falte queda en null o en un valor neutro.

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

num? _num(Object? v) => v is num ? v : num.tryParse(_str(v) ?? '');

DateTime? _date(Object? v) => DateTime.tryParse(_str(v) ?? '')?.toUtc();

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

/// `2026-11-14` → el día calendario (a las 00:00 "UTC"), sin corrimiento de
/// huso: la fecha agendada no tiene hora.
DateTime? _day(Object? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(_str(v) ?? '');
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// `08:00:00` → `08:00`; null si no vino.
String? _hm(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  return s.length >= 5 ? s.substring(0, 5) : s;
}

const _shortWeekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// `vie 14/11`.
String formatShortDay(DateTime d) =>
    '${_shortWeekdays[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}';

/// Un renglón del pedido de una parada.
class RouteBatchItem {
  const RouteBatchItem({required this.name, required this.quantity});

  final String name;
  final int quantity;

  factory RouteBatchItem.fromJson(Map<String, dynamic> j) => RouteBatchItem(
        name: _str(j['name']) ?? 'Garrafa',
        quantity: _num(j['quantity'])?.toInt() ?? 1,
      );
}

/// Una parada del recorrido.
class RouteBatchStop {
  const RouteBatchStop({
    required this.orderId,
    required this.sequence,
    this.active = true,
    this.etaAt,
    this.legDistanceKm = 0,
    this.weightKg = 0,
    this.scheduledDate,
    this.slotStart,
    this.slotEnd,
    this.slotText,
    this.address,
    this.latitude,
    this.longitude,
    this.customerName,
    this.paymentMethod,
    this.totalAmount,
    this.orderStatus,
    this.items = const [],
  });

  final String orderId;

  /// Orden de entrega (1 = primera).
  final int sequence;

  /// Sigue en el lote; con `false` el pedido salió (cancelado o asignado
  /// aparte) y la app no lo muestra.
  final bool active;

  /// Llegada estimada (UTC).
  final DateTime? etaAt;

  /// Km desde la parada anterior (la primera: 0).
  final double legDistanceKm;
  final double weightKg;

  /// Día agendado del pedido (a las 00:00 "UTC"), o null si no vino.
  final DateTime? scheduledDate;

  /// Franja del pedido, `08:00` y `12:00`; null sin franja.
  final String? slotStart;
  final String? slotEnd;

  /// `Mañana 08:00 a 12:00`, o null si el pedido no tiene franja.
  final String? slotText;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? customerName;
  final String? paymentMethod;
  final num? totalAmount;

  /// Estado actual del pedido (`accepted`, `on_the_way`, `delivered`…).
  final String? orderStatus;
  final List<RouteBatchItem> items;

  /// Ya se entregó: en la lista queda como hecha, con su número.
  bool get isDelivered => orderStatus == 'delivered';

  String get itemsText =>
      items.map((i) => '${i.quantity} x ${i.name}').join(', ');

  factory RouteBatchStop.fromJson(Map<String, dynamic> j) {
    final a = _map(j['address']);
    final slot = _map(j['slot']);
    final street = _str(a['street']);
    final city = _str(a['city']);
    final apt = [
      if (_str(a['floor']) != null) 'piso ${a['floor']}',
      if (_str(a['apartment']) != null) 'depto ${a['apartment']}',
    ].join(' ');
    final built = [
      if (street != null) street,
      if (apt.isNotEmpty) apt,
      if (city != null) city,
    ].join(', ');
    return RouteBatchStop(
      orderId: _str(j['orderId']) ?? '',
      sequence: _num(j['sequence'])?.toInt() ?? 0,
      active: j['active'] != false,
      etaAt: _date(j['etaAt']),
      legDistanceKm: _num(j['legDistanceKm'])?.toDouble() ?? 0,
      weightKg: _num(j['weightKg'])?.toDouble() ?? 0,
      scheduledDate: _day(j['scheduledDate']),
      slotStart: slot.isEmpty ? null : _hm(slot['startTime']),
      slotEnd: slot.isEmpty ? null : _hm(slot['endTime']),
      slotText: slot.isEmpty ? null : _slotText(slot),
      address: _str(a['formattedAddress']) ?? (built.isEmpty ? null : built),
      latitude: _num(a['latitude'])?.toDouble(),
      longitude: _num(a['longitude'])?.toDouble(),
      customerName: _str(j['customerName']),
      paymentMethod: _str(j['paymentMethod']),
      totalAmount: _num(j['totalAmount']),
      orderStatus: _str(j['orderStatus']),
      items: [
        if (j['items'] is List)
          for (final i in (j['items'] as List).whereType<Map>())
            RouteBatchItem.fromJson(Map<String, dynamic>.from(i)),
      ],
    );
  }

  static String? _slotText(Map<String, dynamic> slot) {
    String hm(Object? v) {
      final s = _str(v);
      return s == null ? '' : (s.length >= 5 ? s.substring(0, 5) : s);
    }

    final from = hm(slot['startTime']);
    final to = hm(slot['endTime']);
    final name = _str(slot['name']);
    final range = from.isEmpty || to.isEmpty ? null : '$from a $to';
    if (name == null) return range;
    return range == null ? name : '$name $range';
  }
}

/// La oferta del lote al chofer.
class RouteBatchOffer {
  const RouteBatchOffer({
    required this.offerId,
    required this.status,
    required this.expiresAt,
  });

  final String offerId;

  /// `pending` | `accepted` | `rejected` | `expired`.
  final String status;
  final DateTime expiresAt;

  bool get isPending => status == 'pending';

  /// Falta para que venza (nunca negativo).
  Duration remaining(DateTime now) {
    final d = expiresAt.difference(now.toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  static RouteBatchOffer? fromJson(Object? raw) {
    final j = _map(raw);
    final expires = _date(j['expiresAt']);
    if (j.isEmpty || expires == null) return null;
    return RouteBatchOffer(
      offerId: _str(j['offerId']) ?? '',
      status: _str(j['status']) ?? 'pending',
      expiresAt: expires,
    );
  }
}

/// Un recorrido tal como lo ve el chofer (`DriverRouteBatchResponseDto`).
class RouteBatch {
  const RouteBatch({
    required this.batchId,
    required this.status,
    this.totalWeightKg = 0,
    this.stopCount = 0,
    this.offer,
    this.allStops = const [],
  });

  final String batchId;

  /// `offered` | `assigned` | `dissolved` | `completed`.
  final String status;
  final double totalWeightKg;
  final int stopCount;
  final RouteBatchOffer? offer;
  final List<RouteBatchStop> allStops;

  /// Las paradas que siguen en el lote, en orden de entrega. Se numeran por
  /// su posición en esta lista (1..M), no por `sequence`: si una parada sale
  /// del lote, las que siguen corren un lugar.
  List<RouteBatchStop> get stops => [
        for (final s in allStops)
          if (s.active) s
      ]..sort((a, b) => a.sequence.compareTo(b.sequence));

  /// Espera la respuesta del chofer.
  bool get awaitsAnswer => status == 'offered' && (offer?.isPending ?? false);

  double get totalDistanceKm => stops.fold(0, (a, s) => a + s.legDistanceKm);

  /// El chofer lo aceptó y lo está repartiendo.
  bool get isAssigned => status == 'assigned';

  /// Cuándo es el recorrido, con fecha y hora reales: desde que abre la
  /// primera franja hasta que cierra la última.
  /// - Todo el mismo día: `vie 13/11, 08:00–12:00`.
  /// - Si pasa de un día a otro: `vie 13/11 22:00 a sáb 14/11 03:00`.
  /// - Sin franjas: sólo los días (`vie 13/11` o `vie 13/11 y sáb 14/11`).
  /// - null si el back no mandó la fecha.
  ///
  /// En SPLG una franja no cruza la medianoche (el back exige inicio < fin);
  /// si alguna llegara con el fin antes del inicio, se toma el fin al día
  /// siguiente.
  String? get scheduleText {
    final active = stops;
    final days = {
      for (final s in active)
        if (s.scheduledDate != null) s.scheduledDate!
    }.toList()
      ..sort();
    if (days.isEmpty) return null;
    DateTime? start;
    DateTime? end;
    for (final s in active) {
      final day = s.scheduledDate;
      final from = _clock(s.slotStart);
      final to = _clock(s.slotEnd);
      if (day == null || from == null || to == null) continue;
      final opens = day.add(from);
      final closes = day.add(to <= from ? to + const Duration(days: 1) : to);
      if (start == null || opens.isBefore(start)) start = opens;
      if (end == null || closes.isAfter(end)) end = closes;
    }
    if (start == null || end == null) {
      return days.map(formatShortDay).join(' y ');
    }
    if (_sameDay(start, end)) {
      return '${formatShortDay(start)}, ${_hhmm(start)}–${_hhmm(end)}';
    }
    return '${formatShortDay(start)} ${_hhmm(start)} a '
        '${formatShortDay(end)} ${_hhmm(end)}';
  }

  static Duration? _clock(String? hm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hm ?? '');
    if (m == null) return null;
    return Duration(hours: int.parse(m[1]!), minutes: int.parse(m[2]!));
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Número de parada (1 = primera) del pedido [orderId] entre las que siguen
  /// en el lote; null si no es una de ellas.
  int? stopNumberOf(String orderId) {
    final i = stops.indexWhere((s) => s.orderId == orderId);
    return i < 0 ? null : i + 1;
  }

  factory RouteBatch.fromJson(Map<String, dynamic> j) => RouteBatch(
        batchId: _str(j['batchId']) ?? '',
        status: _str(j['status']) ?? 'offered',
        totalWeightKg: _num(j['totalWeightKg'])?.toDouble() ?? 0,
        stopCount: _num(j['stopCount'])?.toInt() ?? 0,
        offer: RouteBatchOffer.fromJson(j['offer']),
        allStops: [
          if (j['stops'] is List)
            for (final s in (j['stops'] as List).whereType<Map>())
              RouteBatchStop.fromJson(Map<String, dynamic>.from(s)),
        ],
      );
}

/// Aviso en vivo de un recorrido (socket `route-batch:*`).
sealed class RouteBatchEvent {
  const RouteBatchEvent(this.batchId);

  final String batchId;
}

/// `route-batch:offer`: hay una oferta nueva; el detalle se lee con `GET`.
class RouteBatchOffered extends RouteBatchEvent {
  const RouteBatchOffered(super.batchId, {this.expiresAt});

  final DateTime? expiresAt;
}

/// `route-batch:offer-closed`: la oferta se cerró (`expired`, `dissolved` o
/// `withdrawn`).
class RouteBatchClosed extends RouteBatchEvent {
  const RouteBatchClosed(super.batchId, this.reason);

  final String? reason;
}

/// `route-batch:assigned`: al aceptar, los pedidos en el orden del recorrido.
class RouteBatchAssigned extends RouteBatchEvent {
  const RouteBatchAssigned(super.batchId, this.orderIds);

  final List<String> orderIds;
}

/// Lee el payload de un evento del socket; null si no trae `batchId`.
RouteBatchEvent? parseRouteBatchEvent(String event, Map<String, dynamic> j) {
  final id = _str(j['batchId']);
  if (id == null) return null;
  return switch (event) {
    'route-batch:offer' =>
      RouteBatchOffered(id, expiresAt: _date(j['expiresAt'])),
    'route-batch:offer-closed' => RouteBatchClosed(id, _str(j['reason'])),
    'route-batch:assigned' => RouteBatchAssigned(id, [
        if (j['orderIds'] is List)
          for (final o in j['orderIds'] as List) o.toString(),
      ]),
    _ => null,
  };
}

/// Resultado de aceptar o rechazar (`DriverRouteBatchDecisionDto`).
class RouteBatchDecision {
  const RouteBatchDecision(
      {required this.batchId,
      required this.accepted,
      required this.assignedOrders});

  final String batchId;
  final bool accepted;
  final int assignedOrders;

  factory RouteBatchDecision.fromJson(Map<String, dynamic> j) =>
      RouteBatchDecision(
        batchId: _str(j['batchId']) ?? '',
        accepted: j['accepted'] == true,
        assignedOrders: _num(j['assignedOrders'])?.toInt() ?? 0,
      );
}
