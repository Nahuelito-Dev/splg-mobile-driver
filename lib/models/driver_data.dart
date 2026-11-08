// Modelos de lectura de la app del chofer (perfil, vehículo, entregas y
// calificación). Los arma `DriverApiService` desde las respuestas del back.

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

num _num(Object? v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

class DriverProfile {
  const DriverProfile({
    required this.userId,
    required this.fullName,
    this.deliveryId,
    this.email,
    this.phone,
  });

  final String userId;
  final String? deliveryId;
  final String fullName;
  final String? email;
  final String? phone;

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    final delivery = json['delivery'];
    return DriverProfile(
      userId: json['user_id'].toString(),
      deliveryId: delivery is Map ? _str(delivery['delivery_id']) : null,
      fullName: _str(json['full_name']) ?? 'Chofer',
      email: _str(json['email']),
      phone: _str(json['phone_number']),
    );
  }
}

class DriverVehicle {
  const DriverVehicle({
    required this.brand,
    required this.model,
    required this.patent,
    this.type,
    this.assignedAt,
  });

  final String brand;
  final String model;
  final String patent;
  final String? type;
  final DateTime? assignedAt;

  factory DriverVehicle.fromJson(Map<String, dynamic> json) => DriverVehicle(
        brand: _str(json['carBrand']) ?? '-',
        model: _str(json['carModel']) ?? '-',
        patent: _str(json['carPatent']) ?? '-',
        type: _str(json['carTypeCar']),
        assignedAt:
            DateTime.tryParse(_str(json['assignedAt']) ?? '')?.toLocal(),
      );
}

class OrderLine {
  const OrderLine({
    required this.label,
    required this.quantity,
    this.gasCylinderId,
    this.containersCharged = 0,
    int? emptiesExpected,
    this.emptiesReceived,
  }) : _emptiesExpected = emptiesExpected;

  /// Un renglón de `order_items[]` del pedido. Tolerante: un pedido sin los
  /// campos de F35 espera una vacía por unidad y no tiene vacías declaradas.
  factory OrderLine.fromJson(Map<dynamic, dynamic> json) {
    final cylinder = json['gas_cylinder'];
    final quantity = _num(json['quantity']).toInt();
    final charged = _num(json['containersCharged']).toInt();
    final expected = json['emptiesExpected'];
    final received = json['emptiesReceived'];
    return OrderLine(
      label: _str(cylinder is Map ? cylinder['type'] : null) ?? 'Producto',
      quantity: quantity,
      gasCylinderId: _str(cylinder is Map ? cylinder['gas_cylinder_id'] : null),
      containersCharged: charged,
      emptiesExpected: expected == null ? null : _num(expected).toInt(),
      emptiesReceived: received == null ? null : _num(received).toInt(),
    );
  }

  final String label;
  final int quantity;

  /// Tipo de garrafa del renglón (`gas_cylinder.gas_cylinder_id`).
  final String? gasCylinderId;

  /// Envases que el cliente compró en este renglón: por esos no devuelve vacía.
  final int containersCharged;
  final int? _emptiesExpected;

  /// Vacías declaradas por el chofer; null = no declaró (se toman las
  /// esperadas).
  final int? emptiesReceived;

  /// Vacías del canje que el chofer tiene que recibir (el back las calcula:
  /// cantidad menos envases comprados), entre 0 y la cantidad. Un pedido sin
  /// el campo espera una por unidad.
  int get emptiesExpected {
    final n = _emptiesExpected ?? quantity;
    if (n < 0) return 0;
    return n > quantity ? quantity : n;
  }
}

/// Estados de pedido que devuelve el back (`OrderStatus`).
enum DriverOrderStatus {
  reserved('Reservado'),
  pending('Pendiente'),
  accepted('Aceptado'),
  onTheWay('En camino'),
  delivered('Entregado'),
  cancelled('Cancelado');

  const DriverOrderStatus(this.label);
  final String label;

  static DriverOrderStatus parse(String? raw) => switch (raw) {
        'reserved' => reserved,
        'accepted' => accepted,
        'on_the_way' || 'out_for_delivery' => onTheWay,
        'delivered' => delivered,
        'cancelled' => cancelled,
        _ => pending,
      };
}

class DriverOrder {
  const DriverOrder({
    required this.id,
    required this.status,
    required this.total,
    required this.createdAt,
    this.deliveredAt,
    this.paymentMethod,
    this.paymentStatus,
    this.depositAmount = 0,
    this.depositPaid = false,
    this.remainingBalance,
    this.address,
    this.customerName,
    this.cancellationReason,
    this.lines = const [],
  });

  final String id;
  final DriverOrderStatus status;
  final num total;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final String? paymentMethod;

  /// `pending`, `paid`, `unpaid`… (`paymentStatus` del back).
  final String? paymentStatus;

  /// Seña de la reserva y saldo a cobrar al entregar (total - seña paga).
  final num depositAmount;
  final bool depositPaid;
  final num? remainingBalance;
  final String? address;
  final String? customerName;
  final String? cancellationReason;
  final List<OrderLine> lines;

  /// Lo que se cobró (o se cobra) en la entrega: el saldo si la seña ya estaba
  /// paga, si no el total. Es la única cifra de "monto" que usa la app, igual
  /// que la pantalla de cobro.
  num get amountToCollect => depositPaid ? (remainingBalance ?? total) : total;

  /// Fecha que se muestra: la entrega si ya se hizo, si no la del pedido.
  DateTime get date => deliveredAt ?? createdAt;

  /// Entregado en efectivo y todavía sin cobrar ni informar como impago: al
  /// chofer le falta pasar por la pantalla de cobro.
  bool get isCashCollectionPending =>
      status == DriverOrderStatus.delivered &&
      paymentMethod == 'cash' &&
      paymentStatus == 'pending';

  factory DriverOrder.fromJson(Map<String, dynamic> json) {
    final address = json['delivery_address'];
    final customer = json['customer'];
    final items = json['order_items'];
    return DriverOrder(
      id: json['order_id'].toString(),
      status: DriverOrderStatus.parse(_str(json['status'])),
      total: _num(json['total_amount']),
      createdAt: DateTime.tryParse(_str(json['created_at']) ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deliveredAt: DateTime.tryParse(_str(json['actual_delivery_date']) ?? '')
          ?.toLocal(),
      paymentMethod: _str(json['payment_method']),
      paymentStatus: _str(json['paymentStatus']),
      depositAmount: _num(json['depositAmount']),
      depositPaid: json['depositPaid'] == true,
      remainingBalance: json['remainingBalance'] == null
          ? null
          : _num(json['remainingBalance']),
      address: address is Map
          ? (_str(address['formatted_address']) ?? _str(address['street']))
          : null,
      customerName: customer is Map ? _str(customer['full_name']) : null,
      cancellationReason: _str(json['cancellation_reason']),
      lines: items is List
          ? [
              for (final i in items.whereType<Map>())
                OrderLine(
                  label:
                      _str((i['gas_cylinder'] as Map?)?['type']) ?? 'Producto',
                  quantity: _num(i['quantity']).toInt(),
                ),
            ]
          : const [],
    );
  }
}

/// Una página del historial de entregas.
class OrdersPage {
  const OrdersPage({
    required this.orders,
    required this.total,
    required this.offset,
  });

  final List<DriverOrder> orders;

  /// Total de pedidos del chofer en el back (no sólo los de esta página).
  final int total;
  final int offset;

  int get nextOffset => offset + orders.length;
  bool get hasMore => orders.isNotEmpty && nextOffset < total;
}

/// Lo entregado en un día y lo que había que cobrar de eso, tal como lo
/// calcula el back (`GET /api/v2/reports/delivery/me/daily-totals`).
class DayTotal {
  const DayTotal({
    required this.day,
    required this.deliveredOrders,
    required this.totalAmount,
  });

  /// `YYYY-MM-DD`, en hora argentina.
  final String day;
  final int deliveredOrders;
  final num totalAmount;

  factory DayTotal.fromJson(Map<String, dynamic> json) => DayTotal(
        day: _str(json['day']) ?? '',
        deliveredOrders: _num(json['deliveredOrders']).toInt(),
        totalAmount: _num(json['totalAmount']),
      );
}

class RatingSummary {
  const RatingSummary({required this.average, required this.count});
  final double average;
  final int count;

  factory RatingSummary.fromJson(Map<String, dynamic> json) => RatingSummary(
        average: _num(json['average']).toDouble(),
        count: _num(json['count']).toInt(),
      );
}

/// `$14.900` (separador de miles con punto, sin decimales si son cero).
String formatMoney(num amount) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(amount % 1 == 0 ? 0 : 2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  final decimals = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '-' : ''}\$$buf$decimals';
}

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String formatDateTime(DateTime d) =>
    '${formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// `Sábado 10 de octubre`.
String formatLongDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} de ${_months[d.month - 1]}';

/// `09:05`.
String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
