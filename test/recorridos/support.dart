import 'package:dio/dio.dart';
import 'package:splg_driver/models/cylinder_pickup.dart';
import 'package:splg_driver/models/route_batch.dart';

DioException http(int? code, [dynamic data]) => DioException(
    requestOptions: RequestOptions(path: ''),
    type: code == null
        ? DioExceptionType.connectionError
        : DioExceptionType.badResponse,
    response: code == null
        ? null
        : Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: code,
            data: data));

Response<dynamic> res(Object data, [int status = 200]) => Response(
    requestOptions: RequestOptions(path: ''), data: data, statusCode: status);

Map<String, dynamic> stopJson(
  String orderId,
  int sequence, {
  bool active = true,
  double leg = 1.5,
}) =>
    {
      'orderId': orderId,
      'sequence': sequence,
      'active': active,
      'etaAt': '2026-11-03T12:30:00.000Z',
      'legDistanceKm': sequence == 1 ? 0 : leg,
      'weightKg': 25,
      'scheduledDate': '2026-11-03',
      'slot': {
        'name': 'Mañana',
        'startTime': '08:00:00',
        'endTime': '12:00:00'
      },
      'address': {
        'street': 'Av. Corrientes 1234',
        'city': 'Posadas',
        'floor': null,
        'apartment': null,
        'formattedAddress': 'Av. Corrientes 1234, Posadas',
        'latitude': -27.3671,
        'longitude': -55.8961,
      },
      'customerName': 'Cliente $sequence',
      'paymentMethod': 'cash',
      'totalAmount': 12000,
      'orderStatus': 'accepted',
      'items': [
        {'name': 'Garrafa 10 kg', 'quantity': 2},
      ],
    };

/// `DriverRouteBatchResponseDto` con una oferta que vence en [ttl].
Map<String, dynamic> batchJson({
  String id = 'b1',
  String status = 'offered',
  String offerStatus = 'pending',
  Duration ttl = const Duration(seconds: 60),
  List<Map<String, dynamic>>? stops,
}) =>
    {
      'batchId': id,
      'status': status,
      'totalWeightKg': 75.5,
      'stopCount': 3,
      'createdAt': '2026-11-03T10:00:00.000Z',
      'offer': {
        'offerId': 'of1',
        'status': offerStatus,
        'expiresAt': DateTime.now().add(ttl).toUtc().toIso8601String(),
        'respondedAt': null,
      },
      'stops': stops ??
          [
            stopJson('o1', 1),
            stopJson('o2', 2),
            stopJson('o3', 3, active: false),
          ],
    };

RouteBatch batch({
  String id = 'b1',
  Duration ttl = const Duration(seconds: 60),
  List<Map<String, dynamic>>? stops,
}) =>
    RouteBatch.fromJson(batchJson(id: id, ttl: ttl, stops: stops));

Map<String, dynamic> pickupJson({
  String noticeId = 'n1',
  String orderId = 'o1',
  String orderStatus = 'accepted',
}) =>
    {
      'noticeId': noticeId,
      'caseId': 'c1',
      'orderId': orderId,
      'orderStatus': orderStatus,
      'scheduledDate': '2026-11-04',
      'serial': 'SPLG-00042',
      'product': '10kg',
      'depositAmount': 25000,
      'customerName': 'Cliente Prueba',
      'customerPhone': '+5493815550003',
    };

CylinderPickup pickup({
  String noticeId = 'n1',
  String orderId = 'o1',
  String orderStatus = 'accepted',
}) =>
    CylinderPickup.fromJson(pickupJson(
        noticeId: noticeId, orderId: orderId, orderStatus: orderStatus));
