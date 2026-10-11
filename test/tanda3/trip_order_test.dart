import 'package:flutter_test/flutter_test.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';

import 'support.dart';

void main() {
  test('lee el pedido con la forma real del back', () {
    final o = TripOrder.fromJson(orderJson());
    expect(o.id, 'o1');
    expect(o.status, DriverOrderStatus.accepted);
    expect(o.total, 28310);
    expect(o.isCash, true);
    expect(o.isPaid, false);
    expect(o.customerName, 'Cliente Prueba');
    expect(o.customerPhone, '+5493815550003');
    expect(o.address, 'Buenos Aires 4114, Centro, Posadas, Misiones');
    expect(o.lat, closeTo(-27.357482, 1e-6));
    expect(o.hasCoordinates, true);
    expect(o.windowText, '08:00 a 12:00');
    expect(o.linesText, '2 x Garrafa 10kg');
    expect(o.instructions, 'Timbre 2');
  });

  test('"out_for_delivery" del back es en camino', () {
    expect(trip(status: 'out_for_delivery').status, DriverOrderStatus.onTheWay);
    expect(trip(status: 'on_the_way').status, DriverOrderStatus.onTheWay);
  });

  test('tolera un pedido pelado: sin dirección, cliente ni items', () {
    final o = TripOrder.fromJson({'order_id': 'x', 'status': 'pending'});
    expect(o.total, 0);
    expect(o.address, isNull);
    expect(o.hasCoordinates, false);
    expect(o.windowText, isNull);
    expect(o.lines, isEmpty);
    expect(o.isCash, false);
  });

  test('pago online pagado', () {
    final o = trip(method: 'online', paymentStatus: 'paid');
    expect(o.isCash, false);
    expect(o.isPaid, true);
  });
}
