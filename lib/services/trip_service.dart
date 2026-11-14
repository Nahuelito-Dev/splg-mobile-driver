import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/config/app_config.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// El código de entrega del pedido y el estado de los intentos del cliente.
class DeliveryCodeInfo {
  const DeliveryCodeInfo(this.code, {this.attempts = 0, this.blocked = false});

  final String code;

  /// Códigos incorrectos del cliente desde el último código nuevo.
  final int attempts;

  /// El cliente agotó los intentos: hay que generar un código nuevo.
  final bool blocked;
}

/// Llamadas del chofer sobre un pedido en curso: leerlo, aceptarlo, salir,
/// avisar la llegada, liberarlo, pedir el código del QR y calificar al cliente. Cada
/// método lanza si el back falla; las pantallas muestran el texto con
/// `ApiErrorText`.
///
/// Los PATCH/POST idempotentes reusan la misma `Idempotency-Key` mientras el
/// intento siga sin respuesta del back (red caída): un reintento no duplica la
/// acción. Con una respuesta definitiva (éxito o rechazo de negocio) la clave se
/// descarta; ante 5xx, 429, el 409 "en curso" y el 422 de clave ya usada se
/// conserva (el primer envío pudo haber llegado).
class TripService {
  TripService({ApiClient? api, DriverAuthService? auth, Uuid? uuid})
      : _api = api ?? ApiClient(),
        _authOverride = auth,
        _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final DriverAuthService? _authOverride;
  final Uuid _uuid;
  final Map<String, String> _keys = {};

  /// Pedido que el chofer tiene en curso en esta sesión (null = ninguno). Lo
  /// observa el Inicio: mientras haya uno no se abren ni se buscan ofertas.
  String? activeOrderId;
  Completer<void>? _flow;

  /// Arranca el flujo de un pedido (en curso -> QR -> cobro -> completado).
  void beginFlow(String orderId) {
    if (activeOrderId != orderId) paymentOpenedFor = null;
    activeOrderId = orderId;
    _flow ??= Completer<void>();
  }

  /// Pedido del flujo cuya pantalla de cobro ya se abrió. La abre la pantalla
  /// del QR al confirmarse la entrega; la del pedido, que queda abajo, no la
  /// vuelve a abrir al recuperar el control.
  String? paymentOpenedFor;

  /// Espera a que el flujo TERMINE de verdad (completado, cancelado o
  /// liberado), no cuando una pantalla del flujo reemplaza a otra.
  Future<void> waitFlow() => _flow?.future ?? Future<void>.value();

  /// Fin del flujo: libera al Inicio.
  void endFlow() {
    activeOrderId = null;
    paymentOpenedFor = null;
    final f = _flow;
    _flow = null;
    if (f != null && !f.isCompleted) f.complete();
  }

  /// Cierre de sesión: descarta claves de idempotencia y cualquier flujo.
  void reset() {
    _keys.clear();
    endFlow();
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
      if (!keepIdempotencyKey(e)) _keys.remove(action);
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

  /// `PATCH /orders/:id/cancel` con el rol chofer: el back no lo cancela, lo
  /// libera (vuelve a pendiente para otro chofer). El chofer no manda motivo.
  Future<void> release(String id) {
    final action = 'release:$id';
    return _once(action, () async {
      await _api.patch(
          'orders/$id/cancel', const {}, await _token(), _idem(action));
    });
  }

  /// `PATCH /api/v2/orders/:id/arrived` con la posición actual del chofer:
  /// avisa al cliente, no cambia el estado. Si el chofer todavía está lejos del
  /// domicilio el back rechaza con 409 `ARRIVAL_TOO_FAR` (ver
  /// [isArrivalTooFar]). La clave es una por intención (pedido + posición): un
  /// reintento sin respuesta con la misma posición la reusa; con otra posición
  /// es otro aviso.
  Future<void> arrived(String id,
      {required double latitude, required double longitude}) {
    final action = 'arrived:$id:${latitude.toStringAsFixed(6)},'
        '${longitude.toStringAsFixed(6)}';
    return _once(action, () async {
      await _api.patch(
        '${AppConfig.apiV2Url}orders/$id/arrived',
        {'latitude': latitude, 'longitude': longitude},
        await _token(),
        _idem(action),
      );
    });
  }

  /// `GET /orders/:id/delivery-code`: el texto que va en el QR y cuántos
  /// códigos incorrectos lleva el cliente (`attempts`, `blocked`).
  Future<DeliveryCodeInfo> deliveryCode(String id) async {
    final res = await _api.get('orders/$id/delivery-code', await _token());
    final data = res.data is Map ? res.data as Map : const {};
    final code = data['deliveryCode']?.toString();
    if (code == null || code.isEmpty) {
      throw StateError('El pedido no tiene código de entrega todavía.');
    }
    final attempts = data['attempts'];
    return DeliveryCodeInfo(
      code,
      attempts: attempts is num ? attempts.toInt() : 0,
      blocked: data['blocked'] == true,
    );
  }

  /// `POST /api/v2/orders/:id/delivery-code/regenerate`: un código nuevo (6
  /// dígitos) que reemplaza al anterior y vuelve a 0 los intentos del cliente.
  /// Devuelve el código nuevo.
  Future<String> regenerateDeliveryCode(String id) {
    final action = 'regenerate-code:$id';
    return _once(action, () async {
      final res = await _api.post(
        '${AppConfig.apiV2Url}orders/$id/delivery-code/regenerate',
        const {},
        await _token(),
        _idem(action),
      );
      final code =
          res.data is Map ? res.data['deliveryCode']?.toString() : null;
      if (code == null || code.isEmpty) {
        throw StateError('No pudimos generar el código nuevo.');
      }
      return code;
    });
  }

  /// `PATCH /api/v2/orders/:id/empties`: las vacías que el cliente le dio al
  /// chofer, por tipo de garrafa (`{gasCylinderId: emptiesReceived}`).
  /// Devuelve el pedido actualizado. La clave es una por intención (pedido +
  /// valores declarados): un reintento sin respuesta la reusa.
  Future<TripOrder> declareEmpties(String id, Map<String, int> received) {
    // Mismo orden en la clave y en el cuerpo: el hash del back respeta el orden.
    final ids = received.keys.toList()..sort();
    final items = [
      for (final k in ids) {'gasCylinderId': k, 'emptiesReceived': received[k]},
    ];
    final action =
        'empties:$id:${ids.map((k) => '$k=${received[k]}').join(',')}';
    return _once(action, () async {
      final res = await _api.patch(
        '${AppConfig.apiV2Url}orders/$id/empties',
        {'items': items},
        await _token(),
        _idem(action),
      );
      final data = res.data;
      if (data is Map && data['order_id'] != null) {
        return TripOrder.fromJson(Map<String, dynamic>.from(data));
      }
      return order(id);
    });
  }

  /// `POST /incidents`: reporta una incidencia de la entrega. La clave es una
  /// por intención (acción + pedido + tipo): un reintento sin respuesta la
  /// reusa.
  Future<Response> reportIncident(
      String orderId, String type, String description) {
    final action = 'incident:$orderId:$type';
    return _once(action, () async {
      return _api.post(
        'incidents',
        {'orderId': orderId, 'type': type, 'description': description},
        await _token(),
        _idem(action),
      );
    });
  }

  /// `POST /cylinders/assign`: asigna y despacha envases (por serial) a un
  /// pedido. Misma regla de clave que [reportIncident], con los envases como
  /// parte de la intención.
  Future<Response> assignCylinders(String orderId, List<String> serials) {
    // Mismo orden en la clave y en el cuerpo: el hash del back respeta el orden.
    final sorted = [...serials]..sort();
    final action = 'cylinders:$orderId:${sorted.join(',')}';
    return _once(action, () async {
      return _api.post(
        'cylinders/assign',
        {'orderId': orderId, 'serials': sorted},
        await _token(),
        _idem(action),
      );
    });
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
