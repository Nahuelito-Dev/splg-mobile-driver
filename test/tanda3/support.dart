import 'package:geolocator/geolocator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';

/// Pedido de prueba con la forma real de `GET /orders/:id`.
Map<String, dynamic> orderJson({
  String status = 'accepted',
  String method = 'cash',
  String paymentStatus = 'pending',
  num total = 28310,
  String? deliveryId,
}) =>
    {
      if (deliveryId != null) 'delivery_id': deliveryId,
      'order_id': 'o1',
      'status': status,
      'total_amount': total,
      'payment_method': method,
      'paymentStatus': paymentStatus,
      'delivery_window_start': '08:00:00',
      'delivery_window_end': '12:00:00',
      'customer_notes': null,
      'delivery_address': {
        'street': 'Buenos Aires 4114',
        'city': 'Posadas',
        'formatted_address': 'Buenos Aires 4114, Centro, Posadas, Misiones',
        'latitude': '-27.357482',
        'longitude': '-55.890404',
        'additional_instructions': 'Timbre 2',
      },
      'customer': {
        'user_id': 'c1',
        'full_name': 'Cliente Prueba',
        'phone_number': '+5493815550003',
      },
      'order_items': [
        {
          'quantity': 2,
          'gas_cylinder': {'type': 'Garrafa 10kg'}
        }
      ],
    };

TripOrder trip({
  String status = 'accepted',
  String method = 'cash',
  String paymentStatus = 'pending',
  String? deliveryId,
}) =>
    TripOrder.fromJson(orderJson(
        status: status,
        method: method,
        paymentStatus: paymentStatus,
        deliveryId: deliveryId));

const DriverOrderStatus kAccepted = DriverOrderStatus.accepted;

class TripOrderFromJson {
  static TripOrder of(Map<String, dynamic> j) => TripOrder.fromJson(j);
}

/// Posición del chofer en la puerta del pedido de prueba, leída en [at]
/// (por defecto, ahora).
Position fix({
  double lat = -27.357482,
  double lng = -55.890404,
  DateTime? at,
}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: at ?? DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: -1,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
