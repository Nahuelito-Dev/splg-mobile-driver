import 'package:dio/dio.dart';
import 'package:splg_lib/splg_lib.dart';

/// Lo que ve el chofer cuando el back rechaza con 422 porque la misma
/// `Idempotency-Key` ya se usó con otro cuerpo (p. ej. se reintenta un reporte
/// con la nota cambiada): el primer envío llegó, no hay que reenviarlo.
const String kIdempotencyConflictText =
    'Este reporte ya quedó registrado. No hace falta enviarlo de nuevo.';

/// 410 de `GET /orders/:id`: el pedido fue del chofer y ya no lo es.
const String kOrderGoneText = 'El pedido ya no está asignado a vos.';

/// El back dice que el pedido ya no es del chofer: 410 siempre; 404 o 403 (p. ej.
/// el código de entrega tras una reasignación) sólo si [known]: el chofer ya
/// tenía ese pedido en curso en pantalla.
bool isOrderGone(Object e, {bool known = false}) {
  if (e is! DioException) return false;
  final s = e.response?.statusCode;
  return s == 410 || (known && (s == 404 || s == 403));
}

/// Si tras este fallo hay que conservar la `Idempotency-Key` para el próximo
/// intento: sin respuesta (red, timeout), 5xx, 429, el 409 "en curso" y el 422
/// de la clave ya usada. Con éxito o un rechazo de negocio la clave se descarta.
bool keepIdempotencyKey(Object e) {
  if (e is! DioException) return false;
  final status = e.response?.statusCode;
  final data = e.response?.data;
  return ApiErrorText.isRetryable(status) ||
      ApiErrorText.isInProgress(status, data) ||
      isIdempotencyConflict(e);
}

/// 422 de idempotencia del back ("Esa clave de idempotencia ya se usó con
/// otros datos…"). Otros 422 no cuentan.
bool isIdempotencyConflict(Object e) {
  if (e is! DioException || e.response?.statusCode != 422) return false;
  final data = e.response?.data;
  final m = data is Map ? data['message'] : null;
  final text = switch (m) {
    String s => s,
    List l => l.join(' '),
    _ => '',
  };
  return text.toLowerCase().contains('idempoten');
}

/// Texto de respaldo del 409 `ARRIVAL_TOO_FAR` si el back no manda `message`.
const String kArrivalTooFarText =
    'Todavía no estás en el domicilio. Marcá «Llegué» cuando estés en la puerta.';

/// 409 de `PATCH /v2/orders/:id/arrived` con `code: ARRIVAL_TOO_FAR`: el chofer
/// todavía está lejos del domicilio. Otros 409 (estado) no cuentan.
bool isArrivalTooFar(Object e) {
  if (e is! DioException || e.response?.statusCode != 409) return false;
  final data = e.response?.data;
  return data is Map && data['code'] == 'ARRIVAL_TOO_FAR';
}

/// El `message` del 409 `ARRIVAL_TOO_FAR` tal cual lo manda el back (ya viene
/// en castellano, con la distancia); [kArrivalTooFarText] si no trae texto.
String arrivalTooFarText(DioException e) {
  final data = e.response?.data;
  final m = data is Map ? data['message'] : null;
  final text = switch (m) {
    String s => s.trim(),
    List l => l.whereType<String>().join('\n').trim(),
    _ => '',
  };
  return text.isEmpty ? kArrivalTooFarText : text;
}

/// Texto de un fallo al ejecutar una acción: el de idempotencia es propio y el
/// resto sale de [ApiErrorText]; sin respuesta de red o con otro error, [fallback].
String actionErrorText(Object e, {String fallback = ApiErrorText.generic}) {
  if (isIdempotencyConflict(e)) return kIdempotencyConflictText;
  if (e is DioException) {
    if (e.response?.statusCode == 410) return kOrderGoneText;
    return ApiErrorText.of(e.response?.statusCode, e.response?.data);
  }
  return fallback;
}
