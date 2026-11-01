import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/config/app_config.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/core/network/idempotent_poster.dart';
import 'package:splg_driver/models/cylinder_pickup.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Retiros de envases que el cliente aceptó en los pedidos del chofer (CU-108,
/// M5, API v2).
abstract class RecoveryRepository {
  /// `GET /cylinder-recovery/driver/pickups`: pedidos aceptados, en camino o
  /// entregados hace menos de 24 h. Con el módulo apagado, lista vacía.
  Future<List<CylinderPickup>> pickups();

  /// `POST …/pickups/:noticeId/confirm`: registra la devolución y cierra el
  /// caso. 403 fuera del plazo; 404 si no es de un pedido suyo; 409 si el
  /// cliente no aceptó o el caso ya cerró.
  Future<void> confirm(String noticeId);

  /// `POST …/pickups/:noticeId/not-collected {reason}`: el retiro se descarta y
  /// el caso vuelve a su escalón.
  Future<void> notCollected(String noticeId, {required String reason});

  void reset();
}

class HttpRecoveryRepository implements RecoveryRepository {
  HttpRecoveryRepository({ApiClient? api, DriverAuthService? auth})
      : _api = api ?? ApiClient(),
        _authOverride = auth {
    _poster = IdempotentPoster(api: _api);
  }

  static String get basePath =>
      '${AppConfig.apiV2Url}cylinder-recovery/driver/pickups';
  static String confirmPath(String id) => '$basePath/$id/confirm';
  static String notCollectedPath(String id) => '$basePath/$id/not-collected';

  final ApiClient _api;
  final DriverAuthService? _authOverride;
  late final IdempotentPoster _poster;

  DriverAuthService get _auth => _authOverride ?? locator<DriverAuthService>();

  Future<String> _token() async {
    final t = await _auth.token;
    if (t == null) throw StateError('Sin sesión');
    return t;
  }

  @override
  void reset() => _poster.reset();

  @override
  Future<List<CylinderPickup>> pickups() async {
    final r = await _api.get(basePath, await _token());
    final data = r.data;
    return [
      if (data is List)
        for (final p in data.whereType<Map>())
          CylinderPickup.fromJson(Map<String, dynamic>.from(p)),
    ];
  }

  @override
  Future<void> confirm(String noticeId) async {
    await _poster.post(confirmPath(noticeId), const {}, await _token());
  }

  @override
  Future<void> notCollected(String noticeId, {required String reason}) async {
    await _poster.post(
        notCollectedPath(noticeId), {'reason': reason.trim()}, await _token());
  }
}
