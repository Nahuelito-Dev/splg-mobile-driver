import 'package:uuid/uuid.dart';

/// Una intención de envío (registrar el siniestro, la carga, la rendición):
/// fija el contenido (con datos de momento, como la hora del hecho) y la
/// `Idempotency-Key` en el primer intento. Mientras no haya éxito ni rechazo
/// de negocio, los reintentos mandan lo mismo con la misma clave, así un envío
/// que sí llegó no se duplica. Si el chofer cambia el formulario, es otra
/// intención ([reset]).
class SendIntent<T> {
  SendIntent({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  T? _payload;
  String? _key;

  String get key => _key ??= _uuid.v4();

  /// El contenido fijado en el primer intento; [build] se llama una sola vez.
  T payload(T Function() build) => _payload ??= build();

  void reset() {
    _payload = null;
    _key = null;
  }
}
