import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_lib/maps/route_service.dart';

/// Ruta por calles del pedido, pedida al back (`GET /routes/driving?orderId=`).
///
/// La app no lleva clave de Google ni le pega a Google/OSRM: el back consulta
/// al proveedor con la suya y reparte los cupos (30 por minuto, 100 por día por
/// usuario). Ante cualquier falla —cupo agotado, proveedor caído, pedido que ya
/// no está activo, sin posición reciente— devuelve la línea recta sin avisar al
/// usuario, y no vuelve a insistir hasta que pase la espera que corresponde.
///
/// Extiende [SplgRouteService] de `splg-lib` sólo para entrar en
/// `RouteTracker`; cuando la librería exponga una interfaz de ruta, esta clase
/// la implementa y deja de heredar.
class BackendRouteService extends SplgRouteService {
  BackendRouteService({
    required this.orderId,
    required this.tokenProvider,
    this.canRequest,
    Future<Response<dynamic>> Function(String path, String token)? get,
    DateTime Function()? now,
  })  : _get = get ?? ((path, token) => ApiClient().get(path, token)),
        _now = now ?? DateTime.now;

  final String orderId;
  final Future<String?> Function() tokenProvider;

  /// El back da la ruta al chofer asignado con el pedido `accepted` u
  /// `on_the_way`; fuera de eso ni se pregunta.
  final bool Function()? canRequest;

  final Future<Response<dynamic>> Function(String path, String token) _get;
  final DateTime Function() _now;
  DateTime? _pausedUntil;

  /// El último pedido volvió 409: el back todavía no tiene una posición
  /// reciente del chofer (o el pedido no está en un estado que dé ruta).
  bool missingPosition = false;

  /// Cuánto se espera tras cada rechazo antes de volver a preguntar.
  static const Duration tooManyRequestsPause = Duration(minutes: 2);
  static const Duration providerDownPause = Duration(minutes: 1);
  static const Duration notConfiguredPause = Duration(minutes: 10);

  @override
  bool get canRoute => true;

  @override
  Future<SplgRoute> route(LatLng from, LatLng to) async {
    final straight = SplgRoute.straight(from, to);
    missingPosition = false;
    if (!(canRequest?.call() ?? true)) return straight;
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && _now().isBefore(pausedUntil)) return straight;
    try {
      final token = await tokenProvider();
      if (token == null) return straight;
      final response = await _get('routes/driving?orderId=$orderId', token);
      return _parse(response.data) ?? straight;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      missingPosition = status == 409;
      log('ruta del back: ${status ?? e.type}');
      final pause = switch (status) {
        429 => _retryAfter(e.response) ?? tooManyRequestsPause,
        503 => notConfiguredPause,
        502 => providerDownPause,
        int s when s >= 500 => providerDownPause,
        _ => null,
      };
      if (pause != null) _pausedUntil = _now().add(pause);
      return straight;
    } catch (e) {
      log('ruta del back ilegible: ${e.runtimeType}');
      return straight;
    }
  }

  Duration? _retryAfter(Response<dynamic>? response) {
    final seconds = int.tryParse(response?.headers.value('retry-after') ?? '');
    return seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
  }

  SplgRoute? _parse(dynamic data) {
    if (data is! Map) return null;
    final raw = data['points'];
    if (raw is! List) return null;
    final points = <LatLng>[];
    for (final p in raw) {
      if (p is! Map) continue;
      final lat = p['lat'], lng = p['lng'];
      if (lat is num && lng is num) {
        points.add(LatLng(lat.toDouble(), lng.toDouble()));
      }
    }
    if (points.length < 2) return null;
    final distance = data['distanceMeters'];
    final duration = data['durationSeconds'];
    return SplgRoute(
      points: points,
      distanceMeters: distance is num ? distance.toDouble() : 0,
      durationSeconds: duration is num ? duration.round() : null,
      source: data['provider'] == 'google'
          ? RouteSource.directions
          : RouteSource.osrm,
    );
  }
}
