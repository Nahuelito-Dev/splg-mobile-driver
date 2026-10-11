import 'package:flutter_test/flutter_test.dart';
import 'package:splg_driver/models/driver_data.dart';

Map<String, dynamic> orderJson({
  String id = 'o1',
  String status = 'delivered',
  num total = 14900,
  String created = '2026-10-03T21:51:06.327Z',
  String? delivered,
}) =>
    {
      'order_id': id,
      'status': status,
      'total_amount': total,
      'created_at': created,
      'actual_delivery_date': delivered,
      'payment_method': 'cash',
      'delivery_address': {'formatted_address': 'Santa Fe 3957, Posadas'},
      'customer': {'full_name': 'Emilia Villalba'},
      'order_items': [
        {
          'quantity': 2,
          'gas_cylinder': {'type': 'Garrafa 10kg'},
        },
      ],
    };

void main() {
  group('DriverOrder.fromJson', () {
    test('arma el pedido con dirección, cliente y renglones', () {
      final o = DriverOrder.fromJson(orderJson());
      expect(o.id, 'o1');
      expect(o.status, DriverOrderStatus.delivered);
      expect(o.total, 14900);
      expect(o.address, 'Santa Fe 3957, Posadas');
      expect(o.customerName, 'Emilia Villalba');
      expect(o.lines.single.label, 'Garrafa 10kg');
      expect(o.lines.single.quantity, 2);
    });

    test('estado desconocido cae en pendiente y on_the_way en camino', () {
      expect(DriverOrderStatus.parse('algo'), DriverOrderStatus.pending);
      expect(DriverOrderStatus.parse('on_the_way'), DriverOrderStatus.onTheWay);
    });
  });

  test('DriverProfile toma el delivery_id del chofer', () {
    final p = DriverProfile.fromJson({
      'user_id': 'u1',
      'full_name': 'Chofer Prueba',
      'phone_number': '+5493815550004',
      'delivery': {'delivery_id': 'd1'},
    });
    expect(p.deliveryId, 'd1');
    expect(p.phone, '+5493815550004');
  });

  test('DriverVehicle.fromJson', () {
    final v = DriverVehicle.fromJson({
      'carBrand': 'Fiat',
      'carModel': 'Fiorino',
      'carPatent': 'AF123SP',
      'carTypeCar': 'camioneta',
    });
    expect([v.brand, v.model, v.patent, v.type],
        ['Fiat', 'Fiorino', 'AF123SP', 'camioneta']);
  });

  group('EarningsSummary.from', () {
    final now = DateTime(2026, 10, 10, 15);
    DriverOrder at(DateTime d, num total, {String status = 'delivered'}) =>
        DriverOrder.fromJson(orderJson(
          status: status,
          total: total,
          created: d.toUtc().toIso8601String(),
          delivered: d.toUtc().toIso8601String(),
        ));

    test('suma sólo entregados: hoy, últimos 7 días y total', () {
      final s = EarningsSummary.from([
        at(DateTime(2026, 10, 10, 9), 1000),
        at(DateTime(2026, 10, 10, 11), 500),
        at(DateTime(2026, 10, 5, 11), 2000),
        at(DateTime(2026, 9, 1, 11), 4000),
        at(DateTime(2026, 10, 10, 12), 9999, status: 'cancelled'),
      ], now);
      expect(s.today, 1500);
      expect(s.todayCount, 2);
      expect(s.week, 3500);
      expect(s.weekCount, 3);
      expect(s.total, 7500);
      expect(s.totalCount, 4);
      expect(s.lastSevenDays.last, 1500);
      expect(s.lastSevenDays[1], 2000);
    });

    test('ayer y lo que va del mes calendario', () {
      final s = EarningsSummary.from([
        at(DateTime(2026, 10, 10, 9), 1000),
        at(DateTime(2026, 10, 9, 20), 300),
        at(DateTime(2026, 10, 2, 10), 700),
        at(DateTime(2026, 9, 30, 10), 5000),
      ], now);
      expect(s.yesterday, 300);
      expect(s.yesterdayCount, 1);
      expect(s.month, 2000);
      expect(s.monthCount, 3);
      expect(s.total, 7000);
    });

    test('sin entregas todo da cero', () {
      final s = EarningsSummary.from(const [], now);
      expect([s.today, s.week, s.total], [0, 0, 0]);
    });
  });

  test('formatMoney usa punto de miles', () {
    expect(formatMoney(14900), '\$14.900');
    expect(formatMoney(0), '\$0');
    expect(formatMoney(1234567), '\$1.234.567');
    expect(formatMoney(1500.5), '\$1.500,50');
  });
}
