import 'package:splg_driver/models/trip_order.dart';

import '../tanda3/support.dart';

const String k10 = 'gc-10';
const String k15 = 'gc-15';

/// Renglón con la forma de `order_items[]` del back con los campos de F35 E4.
Map<String, dynamic> item(String id, String type, int quantity,
        {int charged = 0, int? expected, int? received, bool f35 = true}) =>
    {
      'quantity': quantity,
      'gas_cylinder': {'gas_cylinder_id': id, 'type': type},
      if (f35) ...{
        'containersCharged': charged,
        'emptiesExpected': expected ?? quantity - charged,
        'emptiesReceived': received,
      },
    };

/// Pedido en camino con 2 x 10 kg (canje completo) y 3 x 15 kg (compró 1
/// envase: espera 2 vacías).
TripOrder tripWithEmpties({
  String status = 'out_for_delivery',
  int? received10,
  int? received15,
}) {
  final j = orderJson(status: status);
  j['order_items'] = [
    item(k10, 'Garrafa 10kg', 2, received: received10),
    item(k15, 'Garrafa 15kg', 3, charged: 1, received: received15),
  ];
  return TripOrder.fromJson(j);
}
