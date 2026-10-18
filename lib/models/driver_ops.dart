// Lo que el chofer hace en el día además de entregar: jornada, rendición,
// comisiones, combustible y siniestros. Lecturas tolerantes: lo que falte
// queda en cero o null, nunca rompe.

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

num _num(Object? v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

num? _numOrNull(Object? v) => v == null ? null : _num(v);

DateTime? _date(Object? v) => DateTime.tryParse(_str(v) ?? '')?.toLocal();

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? [for (final m in v.whereType<Map>()) Map<String, dynamic>.from(m)]
    : const [];

/// `YYYY-MM-DD` (día calendario) para los filtros del back.
String apiDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Jornada del chofer: respuesta de `POST /attendance/mine/check-in|check-out`.
class Workday {
  const Workday({
    required this.id,
    required this.workDate,
    required this.checkInAt,
    this.checkOutAt,
    this.durationMinutes,
  });

  final String id;
  final String workDate;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final int? durationMinutes;

  bool get isOpen => checkOutAt == null;

  /// La jornada es de otro día (día argentino que fijó el back en `workDate`).
  bool isFromPastDay(DateTime now) => workDate != apiDay(now);

  factory Workday.fromJson(Map<String, dynamic> json) => Workday(
        id: _str(json['attendanceId']) ?? '',
        workDate: _str(json['workDate']) ?? '',
        checkInAt: _date(json['checkInAt']) ?? DateTime.now(),
        checkOutAt: _date(json['checkOutAt']),
        durationMinutes: _numOrNull(json['durationMinutes'])?.toInt(),
      );
}

enum SettlementStatus {
  open('Abierta'),
  submitted('Presentada'),
  approved('Aprobada');

  const SettlementStatus(this.label);

  final String label;

  static SettlementStatus parse(String? raw) => switch (raw) {
        'submitted' => submitted,
        'approved' => approved,
        _ => open,
      };
}

class SettlementOrder {
  const SettlementOrder({
    required this.orderId,
    required this.amountToCollect,
    required this.paymentStatus,
    this.deliveredAt,
  });

  final String orderId;
  final num amountToCollect;
  final String paymentStatus;
  final DateTime? deliveredAt;

  factory SettlementOrder.fromJson(Map<String, dynamic> json) =>
      SettlementOrder(
        orderId: _str(json['orderId']) ?? '',
        amountToCollect: _num(json['amountToCollect']),
        paymentStatus: _str(json['paymentStatus']) ?? '',
        deliveredAt: _date(json['deliveredAt']),
      );
}

class SettlementCollection {
  const SettlementCollection(
      {required this.businessName, required this.amount});

  final String businessName;
  final num amount;

  factory SettlementCollection.fromJson(Map<String, dynamic> json) =>
      SettlementCollection(
        businessName: _str(json['businessName']) ?? 'Cuenta corriente',
        amount: _num(json['amount']),
      );
}

class SettlementExpense {
  const SettlementExpense(
      {required this.categoryName, required this.amount, this.description});

  final String categoryName;
  final num amount;
  final String? description;

  factory SettlementExpense.fromJson(Map<String, dynamic> json) =>
      SettlementExpense(
        categoryName: _str(json['categoryName']) ?? 'Gasto',
        amount: _num(json['amount']),
        description: _str(json['description']),
      );
}

/// Rendición del día: `GET /driver-settlements/mine` y su `submit`.
class Settlement {
  const Settlement({
    required this.id,
    required this.number,
    required this.businessDate,
    required this.status,
    required this.expectedCash,
    this.declaredCash,
    this.driverExpenses = 0,
    this.difference,
    this.notes,
    this.orders = const [],
    this.collections = const [],
    this.expenses = const [],
  });

  final String id;
  final int number;
  final String businessDate;
  final SettlementStatus status;
  final num expectedCash;
  final num? declaredCash;
  final num driverExpenses;

  /// Declarado + gastos − esperado: negativa es faltante, positiva sobrante.
  final num? difference;
  final String? notes;
  final List<SettlementOrder> orders;
  final List<SettlementCollection> collections;
  final List<SettlementExpense> expenses;

  bool get isOpen => status == SettlementStatus.open;

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
        id: _str(json['settlementId']) ?? '',
        number: _num(json['number']).toInt(),
        businessDate: _str(json['businessDate']) ?? '',
        status: SettlementStatus.parse(_str(json['status'])),
        expectedCash: _num(json['expectedCash']),
        declaredCash: _numOrNull(json['declaredCash']),
        driverExpenses: _num(json['driverExpenses']),
        difference: _numOrNull(json['difference']),
        notes: _str(json['notes']),
        orders: [
          for (final o in _maps(json['orders'])) SettlementOrder.fromJson(o)
        ],
        collections: [
          for (final c in _maps(json['collections']))
            SettlementCollection.fromJson(c)
        ],
        expenses: [
          for (final e in _maps(json['expenses'])) SettlementExpense.fromJson(e)
        ],
      );
}

/// Categoría de egreso (`GET /cash-categories?direction=expense`).
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.isExpense = true,
    this.isActive = true,
    this.isSystem = false,
  });

  final String id;
  final String name;
  final bool isExpense;
  final bool isActive;

  /// Las de sistema (`systemCode`) las asienta el back; no se eligen a mano.
  final bool isSystem;

  /// Las que el chofer puede elegir en un gasto de la rendición.
  bool get selectable => isExpense && isActive && !isSystem && id.isNotEmpty;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(
        id: _str(json['categoryId']) ?? '',
        name: _str(json['name']) ?? 'Gasto',
        isExpense: _str(json['direction']) == 'expense',
        isActive: json['isActive'] != false,
        isSystem: _str(json['systemCode']) != null,
      );
}

/// Un gasto que el chofer declara al presentar la rendición.
class ExpenseInput {
  const ExpenseInput(
      {required this.categoryId, required this.amount, this.description});

  final String categoryId;
  final num amount;
  final String? description;

  Map<String, dynamic> toJson() => {
        'categoryId': categoryId,
        'amount': amount,
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
      };
}

class CommissionEntry {
  const CommissionEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.occurredAt,
    required this.liquidated,
  });

  final String id;
  final String type;
  final num amount;
  final String description;
  final DateTime? occurredAt;

  /// Ya entró en una liquidación.
  final bool liquidated;

  factory CommissionEntry.fromJson(Map<String, dynamic> json) =>
      CommissionEntry(
        id: _str(json['entryId']) ?? '',
        type: _str(json['type']) ?? '',
        amount: _num(json['amount']),
        description: _str(json['description']) ?? '',
        occurredAt: _date(json['occurredAt']),
        liquidated: _str(json['liquidationId']) != null,
      );
}

/// `GET /commissions/mine?from&to`.
class MyCommissions {
  const MyCommissions({
    this.entries = const [],
    this.total = 0,
    this.totalAmount = 0,
    this.pendingAmount = 0,
    this.liquidatedAmount = 0,
  });

  final List<CommissionEntry> entries;
  final int total;
  final num totalAmount;
  final num pendingAmount;
  final num liquidatedAmount;

  factory MyCommissions.fromJson(Map<String, dynamic> json) => MyCommissions(
        entries: [
          for (final e in _maps(json['data'])) CommissionEntry.fromJson(e)
        ],
        total: _num(json['total']).toInt(),
        totalAmount: _num(json['totalAmount']),
        pendingAmount: _num(json['pendingAmount']),
        liquidatedAmount: _num(json['liquidatedAmount']),
      );
}

/// Cómo se pagó la carga de combustible (`FuelPaymentMethod` del back).
enum FuelPayment {
  driverCash('driver_cash', 'Efectivo mío'),
  cashBox('cash_box', 'Caja de la distribuidora'),
  card('card', 'Tarjeta'),
  fuelAccount('fuel_account', 'Cuenta de combustible');

  const FuelPayment(this.api, this.label);

  final String api;
  final String label;
}

class FuelLoadInput {
  const FuelLoadInput({
    required this.liters,
    required this.unitPrice,
    required this.totalAmount,
    required this.odometerKm,
    required this.paymentMethod,
    this.isFullTank = true,
    this.station,
    this.receiptNumber,
    this.notes,
  });

  final num liters;
  final num unitPrice;
  final num totalAmount;
  final int odometerKm;
  final FuelPayment paymentMethod;
  final bool isFullTank;
  final String? station;
  final String? receiptNumber;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? s) {
      final t = s?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return {
      'liters': liters,
      'unitPrice': unitPrice,
      'totalAmount': totalAmount,
      'odometerKm': odometerKm,
      'paymentMethod': paymentMethod.api,
      'isFullTank': isFullTank,
      if (clean(station) != null) 'station': clean(station),
      if (clean(receiptNumber) != null) 'receiptNumber': clean(receiptNumber),
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// Carga registrada: lo que vuelve de `POST /fleet/fuel-loads/mine`.
class FuelLoadRecord {
  const FuelLoadRecord({
    required this.carPatent,
    required this.liters,
    required this.totalAmount,
    required this.odometerKm,
    required this.anomaly,
  });

  final String? carPatent;
  final num liters;
  final num totalAmount;
  final int odometerKm;
  final bool anomaly;

  factory FuelLoadRecord.fromJson(Map<String, dynamic> json) => FuelLoadRecord(
        carPatent: _str(json['carPatent']),
        liters: _num(json['liters']),
        totalAmount: _num(json['totalAmount']),
        odometerKm: _num(json['odometerKm']).toInt(),
        anomaly: json['anomaly'] == true,
      );
}

class AccidentInput {
  const AccidentInput({
    required this.occurredAt,
    required this.description,
    this.address,
    this.location,
    this.injuries = false,
    this.thirdPartiesInvolved = false,
    this.hazmatRelease = false,
    this.vehicleUnusable = false,
    this.policeReportNumber,
  });

  final DateTime occurredAt;
  final String description;
  final String? address;

  /// `"latitud,longitud"`.
  final String? location;
  final bool injuries;
  final bool thirdPartiesInvolved;
  final bool hazmatRelease;
  final bool vehicleUnusable;
  final String? policeReportNumber;

  Map<String, dynamic> toJson() {
    String? clean(String? s) {
      final t = s?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return {
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      'description': description.trim(),
      if (clean(address) != null) 'address': clean(address),
      if (clean(location) != null) 'location': clean(location),
      'injuries': injuries,
      'thirdPartiesInvolved': thirdPartiesInvolved,
      'hazmatRelease': hazmatRelease,
      'vehicleUnusable': vehicleUnusable,
      if (clean(policeReportNumber) != null)
        'policeReportNumber': clean(policeReportNumber),
    };
  }
}

/// Siniestro registrado (`POST /fleet/accidents/mine`). Si el vehículo quedó
/// inutilizable pero el chofer tiene un pedido o una carga abierta, el back
/// mantiene la asignación (`assignmentKept`) y explica por qué.
class AccidentRecord {
  const AccidentRecord({
    required this.vehicleUnusable,
    this.carPatent,
    this.hazmatRelease = false,
    this.assignmentKept = false,
    this.assignmentKeptReason,
  });

  final bool vehicleUnusable;
  final String? carPatent;
  final bool hazmatRelease;
  final bool assignmentKept;
  final String? assignmentKeptReason;

  factory AccidentRecord.fromJson(Map<String, dynamic> json) => AccidentRecord(
        vehicleUnusable: json['vehicleUnusable'] == true,
        carPatent: _str(json['carPatent']),
        hazmatRelease: json['hazmatRelease'] == true,
        assignmentKept: json['assignmentKept'] == true,
        assignmentKeptReason: _str(json['assignmentKeptReason']),
      );
}
