import 'package:splg_driver/models/driver_data.dart';

String? _s(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

num _n(Object? v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

/// Un pedido tal como lo ve el chofer mientras lo trabaja: lectura de
/// `GET /orders/:id`. Es tolerante: lo que falte queda en null, nunca rompe.
class TripOrder {
  const TripOrder({
    required this.id,
    required this.status,
    required this.total,
    this.paymentMethod,
    this.paymentStatus,
    this.address,
    this.lat,
    this.lng,
    this.instructions,
    this.customerId,
    this.deliveryId,
    this.customerName,
    this.customerPhone,
    this.windowStart,
    this.windowEnd,
    this.notes,
    this.lines = const [],
  });

  final String id;
  final DriverOrderStatus status;
  final num total;

  /// `cash` o `online` (`payment_method` del back).
  final String? paymentMethod;

  /// `pending`, `paid`, etc. (`paymentStatus` del back).
  final String? paymentStatus;
  final String? address;
  final double? lat;
  final double? lng;
  final String? instructions;
  final String? customerId;

  /// Chofer asignado (`delivery_id`), si ya lo tiene.
  final String? deliveryId;
  final String? customerName;
  final String? customerPhone;
  final String? windowStart;
  final String? windowEnd;
  final String? notes;
  final List<OrderLine> lines;

  bool get isCash => paymentMethod == 'cash';
  bool get isPaid => paymentStatus == 'paid';
  bool get hasCoordinates => lat != null && lng != null;

  /// "08:00 a 12:00" si el pedido tiene franja.
  String? get windowText {
    final a = windowStart, b = windowEnd;
    if (a == null || b == null) return null;
    String hm(String t) => t.length >= 5 ? t.substring(0, 5) : t;
    return '${hm(a)} a ${hm(b)}';
  }

  /// "2 x Garrafa 10kg, 1 x Garrafa 15kg".
  String get linesText =>
      lines.map((l) => '${l.quantity} x ${l.label}').join(', ');

  factory TripOrder.fromJson(Map<String, dynamic> json) {
    final address = json['delivery_address'];
    final customer = json['customer'];
    final items = json['order_items'];
    final streetLine = address is Map
        ? (_s(address['formatted_address']) ??
            [_s(address['street']), _s(address['city'])]
                .whereType<String>()
                .join(', '))
        : null;
    return TripOrder(
      id: json['order_id'].toString(),
      status: DriverOrderStatus.parse(_s(json['status'])),
      total: _n(json['total_amount']),
      paymentMethod: _s(json['payment_method']),
      paymentStatus: _s(json['paymentStatus']),
      address: (streetLine == null || streetLine.isEmpty) ? null : streetLine,
      lat: address is Map ? double.tryParse('${address['latitude']}') : null,
      lng: address is Map ? double.tryParse('${address['longitude']}') : null,
      instructions:
          address is Map ? _s(address['additional_instructions']) : null,
      deliveryId: _s(json['delivery_id']),
      customerId: customer is Map ? _s(customer['user_id']) : null,
      customerName: customer is Map ? _s(customer['full_name']) : null,
      customerPhone: customer is Map ? _s(customer['phone_number']) : null,
      windowStart: _s(json['delivery_window_start']),
      windowEnd: _s(json['delivery_window_end']),
      notes: _s(json['customer_notes']),
      lines: items is List
          ? [
              for (final i in items.whereType<Map>())
                OrderLine(
                  label: _s((i['gas_cylinder'] as Map?)?['type']) ?? 'Producto',
                  quantity: _n(i['quantity']).toInt(),
                ),
            ]
          : const [],
    );
  }
}
