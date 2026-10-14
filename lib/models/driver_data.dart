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
  const OrderLine({required this.label, required this.quantity});
  final String label;
  final int quantity;
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

class RatingSummary {
  const RatingSummary({required this.average, required this.count});
  final double average;
  final int count;

  factory RatingSummary.fromJson(Map<String, dynamic> json) => RatingSummary(
        average: _num(json['average']).toDouble(),
        count: _num(json['count']).toInt(),
      );
}

/// Totales de entregas hechas, calculados del historial del chofer.
class EarningsSummary {
  const EarningsSummary({
    required this.today,
    required this.todayCount,
    required this.week,
    required this.weekCount,
    required this.total,
    required this.totalCount,
    required this.lastSevenDays,
    this.yesterday = 0,
    this.yesterdayCount = 0,
    this.month = 0,
    this.monthCount = 0,
  });

  final num today;
  final int todayCount;
  final num week;
  final int weekCount;
  final num total;
  final int totalCount;

  /// Ayer y lo que va del mes calendario.
  final num yesterday;
  final int yesterdayCount;
  final num month;
  final int monthCount;

  /// Monto entregado por día, del más viejo (hace 6 días) a hoy.
  final List<num> lastSevenDays;

  factory EarningsSummary.from(List<DriverOrder> orders, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final perDay = List<num>.filled(7, 0);
    var todayAmount = 0.0, weekAmount = 0.0, totalAmount = 0.0;
    var todayCount = 0, weekCount = 0, totalCount = 0;
    var yesterdayAmount = 0.0, monthAmount = 0.0;
    var yesterdayCount = 0, monthCount = 0;
    // Lo informado impago (o dado de baja) no es ganado.
    for (final o in orders.where((o) =>
        o.status == DriverOrderStatus.delivered &&
        o.paymentStatus != 'unpaid' &&
        o.paymentStatus != 'written_off')) {
      final d = DateTime(o.date.year, o.date.month, o.date.day);
      final daysAgo = today.difference(d).inDays;
      totalAmount += o.amountToCollect;
      totalCount++;
      if (daysAgo >= 0 && daysAgo < 7) {
        weekAmount += o.amountToCollect;
        weekCount++;
        perDay[6 - daysAgo] += o.amountToCollect;
      }
      if (daysAgo == 0) {
        todayAmount += o.amountToCollect;
        todayCount++;
      }
      if (daysAgo == 1) {
        yesterdayAmount += o.amountToCollect;
        yesterdayCount++;
      }
      if (d.year == today.year && d.month == today.month && daysAgo >= 0) {
        monthAmount += o.amountToCollect;
        monthCount++;
      }
    }
    return EarningsSummary(
      today: todayAmount,
      todayCount: todayCount,
      week: weekAmount,
      weekCount: weekCount,
      total: totalAmount,
      totalCount: totalCount,
      lastSevenDays: perDay,
      yesterday: yesterdayAmount,
      yesterdayCount: yesterdayCount,
      month: monthAmount,
      monthCount: monthCount,
    );
  }
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
