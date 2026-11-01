// Retiro de un envase en la entrega (CU-108, M5, API v2): el cliente aceptó
// devolver un envase en el pedido que lleva el chofer.

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

/// Un retiro (`DriverPickupDto`).
class CylinderPickup {
  const CylinderPickup({
    required this.noticeId,
    required this.caseId,
    required this.orderId,
    required this.serial,
    this.orderStatus,
    this.scheduledDate,
    this.product,
    this.depositAmount,
    this.customerName,
    this.customerPhone,
  });

  final String noticeId;
  final String caseId;
  final String orderId;
  final String serial;
  final String? orderStatus;
  final String? scheduledDate;
  final String? product;
  final num? depositAmount;
  final String? customerName;
  final String? customerPhone;

  /// El pedido ya se entregó: queda el plazo de 24 h del back para retirar.
  bool get orderDelivered => orderStatus == 'delivered';

  factory CylinderPickup.fromJson(Map<String, dynamic> j) => CylinderPickup(
        noticeId: _str(j['noticeId']) ?? '',
        caseId: _str(j['caseId']) ?? '',
        orderId: _str(j['orderId']) ?? '',
        serial: _str(j['serial']) ?? '',
        orderStatus: _str(j['orderStatus']),
        scheduledDate: _str(j['scheduledDate']),
        product: _str(j['product']),
        depositAmount: j['depositAmount'] is num
            ? j['depositAmount'] as num
            : num.tryParse(_str(j['depositAmount']) ?? ''),
        customerName: _str(j['customerName']),
        customerPhone: _str(j['customerPhone']),
      );
}
