import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Lo que el chofer le informa al back sobre el cobro del pedido entregado.
/// La pantalla de Cobro programa contra esta interfaz; las rutas y el cuerpo
/// viven sólo en [HttpPaymentRepository].
abstract class PaymentRepository {
  /// "Pago recibido": el chofer cobró en efectivo. `true` si el back dejó el
  /// pedido como pagado.
  Future<bool> confirmReceived(String orderId);

  /// "El cliente no pagó": el back marca el pedido impago y abre una incidencia
  /// con la [note] (opcional). Devuelve el id de la incidencia (para la foto).
  Future<String?> reportUnpaid(String orderId, {String? note});

  /// Sube la foto (JPEG ya limpio) de la incidencia del reporte.
  Future<void> uploadIncidentPhoto(String incidentId, Uint8List jpeg);
}

/// Implementación contra el back (contrato de cobro):
/// - `PATCH /orders/:id/payment/cash-received` (sin cuerpo) -> pedido con
///   `paymentStatus`.
/// - `PATCH /orders/:id/payment/unpaid` (`{note?}` hasta 500) -> `{ incident:
///   { incident_id } }`.
/// - `PUT /incidents/:id/photo` (multipart, campo `file`).
/// Cada intención usa una `Idempotency-Key`, reusada mientras no haya respuesta
/// del back (red caída). Mientras `PAYMENT_API` no sea `true` (por defecto) NO
/// llama al back: la confirmación es sólo local.
class HttpPaymentRepository implements PaymentRepository {
  HttpPaymentRepository({
    ApiClient? api,
    DriverAuthService? auth,
    bool? enabled,
    Uuid? uuid,
  })  : _api = api ?? ApiClient(),
        _authOverride = auth,
        _enabled = enabled ?? _kPaymentApi,
        _uuid = uuid ?? const Uuid();

  static const bool _kPaymentApi =
      bool.fromEnvironment('PAYMENT_API', defaultValue: false);

  static String receivedPath(String orderId) =>
      'orders/$orderId/payment/cash-received';
  static String unpaidPath(String orderId) => 'orders/$orderId/payment/unpaid';
  static String photoPath(String incidentId) => 'incidents/$incidentId/photo';

  final ApiClient _api;
  final DriverAuthService? _authOverride;
  final bool _enabled;
  final Uuid _uuid;
  final Map<String, String> _keys = {};

  DriverAuthService get _auth => _authOverride ?? locator<DriverAuthService>();

  Future<String> _token() async {
    final t = await _auth.token;
    if (t == null) throw StateError('Sin sesión');
    return t;
  }

  Future<Response> _patch(
      String action, String path, Map<String, dynamic> body) async {
    final key = _keys.putIfAbsent(action, _uuid.v4);
    try {
      final r = await _api
          .patch(path, body, await _token(), {'Idempotency-Key': key});
      _keys.remove(action);
      return r;
    } catch (e) {
      // Con respuesta del back (rechazo) la clave se descarta; sin respuesta
      // (red) se conserva para reintentar sin duplicar.
      if (e is DioException && e.response != null) _keys.remove(action);
      rethrow;
    }
  }

  @override
  Future<bool> confirmReceived(String orderId) async {
    if (!_enabled) {
      debugPrint('[Cobro] contrato de pagos no habilitado: sólo local');
      return true;
    }
    final r =
        await _patch('received:$orderId', receivedPath(orderId), const {});
    final data = r.data;
    return data is Map && data['paymentStatus']?.toString() == 'paid';
  }

  @override
  Future<String?> reportUnpaid(String orderId, {String? note}) async {
    if (!_enabled) {
      debugPrint('[Cobro] contrato de pagos no habilitado: sólo local');
      return null;
    }
    final n = note?.trim();
    final r = await _patch('unpaid:$orderId', unpaidPath(orderId), {
      if (n != null && n.isNotEmpty)
        'note': n.length > 500 ? n.substring(0, 500) : n
    });
    final data = r.data;
    final incident = data is Map ? data['incident'] : null;
    return incident is Map ? incident['incident_id']?.toString() : null;
  }

  @override
  Future<void> uploadIncidentPhoto(String incidentId, Uint8List jpeg) async {
    if (!_enabled) return;
    await _api.putFile(
      photoPath(incidentId),
      bytes: jpeg,
      filename: 'incidencia.jpg',
      contentType: 'image/jpeg',
      token: await _token(),
    );
  }
}
