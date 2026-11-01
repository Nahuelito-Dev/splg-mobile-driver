import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/core/network/api_client.dart';

/// `POST` con `Idempotency-Key`: la clave se reusa mientras no haya respuesta
/// del back (red caída, 5xx) para no duplicar la acción, y se descarta con un
/// éxito o un rechazo de negocio.
class IdempotentPoster {
  IdempotentPoster({required this.api, Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final ApiClient api;
  final Uuid _uuid;
  final Map<String, String> _keys = {};

  /// Cierre de sesión: las claves en vuelo eran del chofer anterior.
  void reset() => _keys.clear();

  Future<Response> post(
      String path, Map<String, dynamic> body, String token) async {
    final id = '$path:${jsonEncode(body)}';
    final key = _keys.putIfAbsent(id, _uuid.v4);
    try {
      final r = await api.post(path, body, token, {'Idempotency-Key': key});
      _keys.remove(id);
      return r;
    } catch (e) {
      if (!keepIdempotencyKey(e)) _keys.remove(id);
      rethrow;
    }
  }
}
