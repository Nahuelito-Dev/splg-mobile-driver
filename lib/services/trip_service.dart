import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Llamadas del chofer sobre un pedido en curso: leerlo, aceptarlo, salir,
/// avisar la llegada, pedir el código del QR y calificar al cliente. Cada
/// método lanza si el back falla; las pantallas muestran el texto con
/// `ApiErrorText`.
///
/// Los PATCH/POST idempotentes reusan la misma `Idempotency-Key` mientras el
/// intento siga sin respuesta del back (red caída): un reintento no duplica la
/// acción. Con una respuesta (éxito o rechazo) la clave se descarta.
class TripService {
  TripService({ApiClient? api, DriverAuthService? auth, Uuid? uuid})
      : _api = api ?? ApiClient(),
        _authOverride = auth,
        _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final DriverAuthService? _authOverride;
  final Uuid _uuid;
  final Map<String, String> _keys = {};

  num? _earned;

  /// Pedido que el chofer tiene en curso en esta sesión (null = ninguno). Lo
  /// observa el Inicio: mientras haya uno no se abren ni se buscan ofertas.
  String? activeOrderId;
  Completer<void>? _flow;

  /// Arranca el flujo de un pedido (en curso -> QR -> cobro -> completado).
  void beginFlow(String orderId) {
    activeOrderId = orderId;
    _flow ??= Completer<void>();
  }

  /// Espera a que el flujo TERMINE de verdad (completado, cancelado o
  /// liberado), no cuando una pantalla del flujo reemplaza a otra.
  Future<void> waitFlow() => _flow?.future ?? Future<void>.value();

  /// Fin del flujo: anota lo ganado (si hubo) y libera al Inicio.
  void endFlow({num? earned}) {
    if (earned != null) noteEarned(earned);
    activeOrderId = null;
    final f = _flow;
    _flow = null;
    if (f != null && !f.isCompleted) f.complete();
  }

  /// Cierre de sesión: descarta claves de idempotencia y cualquier flujo.
  void reset() {
    _keys.clear();
    _earned = null;
    endFlow();
  }

  /// Deja anotado lo que ganó el chofer con el pedido que terminó.
  void noteEarned(num amount) => _earned = amount;

  /// Lo anotado por [noteEarned], una sola vez.
  num? takeEarned() {
    final e = _earned;
    _earned = null;
    return e;
  }

  DriverAuthService get _auth => _authOverride ?? locator<DriverAuthService>();

  Future<String> _token() async {
    final t = await _auth.token;
    if (t == null) throw StateError('Sin sesión');
    return t;
  }

  Map<String, String> _idem(String action) =>
      {'Idempotency-Key': _keys.putIfAbsent(action, _uuid.v4)};

  Future<T> _once<T>(String action, Future<T> Function() call) async {
    try {
      final r = await call();
      _keys.remove(action);
      return r;
    } on DioException catch (e) {
      if (e.response != null) _keys.remove(action);
      rethrow;
    }
  }

  /// `GET /orders/:id`.
  Future<TripOrder> order(String id) async {
    final res = await _api.get('orders/$id', await _token());
    return TripOrder.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// `GET /ratings/user/:userId/summary`: null si no se puede leer (la oferta
  /// se muestra igual sin la calificación).
  Future<RatingSummary?> customerRating(String userId) async {
    try {
      final res =
          await _api.get('ratings/user/$userId/summary', await _token());
      return RatingSummary.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (_) {
      return null;
    }
  }

  /// `PATCH /orders/:id/status` con `accepted` u `on_the_way`.
  Future<void> setStatus(String id, String status) {
    final action = 'status:$id:$status';
    return _once(action, () async {
      await _api.patch('orders/$id/status', {'status': status}, await _token(),
          _idem(action));
    });
  }

  /// `POST /orders/:id/reject`.
  Future<void> reject(String id) {
    final action = 'reject:$id';
    return _once(action, () async {
      await _api.post(
          'orders/$id/reject', const {}, await _token(), _idem(action));
    });
  }

  /// `PATCH /orders/:id/arrived`: avisa al cliente, no cambia el estado.
  Future<void> arrived(String id) {
    final action = 'arrived:$id';
    return _once(action, () async {
      await _api.patch(
          'orders/$id/arrived', const {}, await _token(), _idem(action));
    });
  }

  /// `GET /orders/:id/delivery-code`: el texto que va en el QR.
  Future<String> deliveryCode(String id) async {
    final res = await _api.get('orders/$id/delivery-code', await _token());
    final code = res.data is Map ? res.data['deliveryCode']?.toString() : null;
    if (code == null || code.isEmpty) {
      throw StateError('El pedido no tiene código de entrega todavía.');
    }
    return code;
  }

  /// `POST /ratings` (chofer califica al cliente).
  Future<void> rateCustomer(String orderId, int stars, String? comment) {
    final action = 'rate:$orderId';
    final trimmed = comment?.trim();
    return _once(action, () async {
      await _api.post(
        'ratings',
        {
          'orderId': orderId,
          'stars': stars,
          if (trimmed != null && trimmed.isNotEmpty) 'comment': trimmed,
        },
        await _token(),
        _idem(action),
      );
    });
  }
}
