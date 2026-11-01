import 'package:dio/dio.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/config/app_config.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/core/network/idempotent_poster.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Recorridos que el despacho le ofrece al chofer (CU-107, M4, API v2).
abstract class RouteBatchRepository {
  /// `GET /driver/route-batches`: el que espera respuesta primero, después los
  /// que me asignaron.
  Future<List<RouteBatch>> mine({int limit = 20, int offset = 0});

  /// `GET /driver/route-batches/:id`. 404 si no es mío o ya no está vigente.
  Future<RouteBatch> batch(String batchId);

  /// `POST /driver/route-batches/:id/accept`: asigna todos los pedidos, en
  /// orden. 409 si la oferta venció o ya no es mía o los pedidos ya no están;
  /// 400 si el chofer está deshabilitado o con algo vencido.
  Future<RouteBatchDecision> accept(String batchId);

  /// `POST /driver/route-batches/:id/reject`: el lote pasa al siguiente.
  Future<RouteBatchDecision> reject(String batchId);

  /// Cierre de sesión: se descartan las claves de idempotencia en vuelo.
  void reset();
}

class HttpRouteBatchRepository implements RouteBatchRepository {
  HttpRouteBatchRepository({ApiClient? api, DriverAuthService? auth})
      : _api = api ?? ApiClient(),
        _authOverride = auth {
    _poster = IdempotentPoster(api: _api);
  }

  static String get basePath => '${AppConfig.apiV2Url}driver/route-batches';
  static String batchPath(String id) => '$basePath/$id';
  static String acceptPath(String id) => '$basePath/$id/accept';
  static String rejectPath(String id) => '$basePath/$id/reject';

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
  Future<List<RouteBatch>> mine({int limit = 20, int offset = 0}) async {
    final r =
        await _api.get('$basePath?limit=$limit&offset=$offset', await _token());
    final data = r.data;
    final list = data is Map ? data['data'] : data;
    return [
      if (list is List)
        for (final b in list.whereType<Map>())
          RouteBatch.fromJson(Map<String, dynamic>.from(b)),
    ];
  }

  @override
  Future<RouteBatch> batch(String batchId) async =>
      RouteBatch.fromJson(Map<String, dynamic>.from(
          (await _api.get(batchPath(batchId), await _token())).data as Map));

  @override
  Future<RouteBatchDecision> accept(String batchId) async => _decision(
      await _poster.post(acceptPath(batchId), const {}, await _token()));

  @override
  Future<RouteBatchDecision> reject(String batchId) async => _decision(
      await _poster.post(rejectPath(batchId), const {}, await _token()));

  static RouteBatchDecision _decision(Response r) =>
      RouteBatchDecision.fromJson(Map<String, dynamic>.from(r.data as Map));
}
