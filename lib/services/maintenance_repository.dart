import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/config/app_config.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Ventanas de taller que el planificador le propone al chofer (CU-105, API v2).
abstract class MaintenanceRepository {
  /// `GET /driver/maintenance-proposals`: la vigente primero.
  Future<MaintenancePage> proposals({int limit = 50, int offset = 0});

  /// `GET /driver/maintenance-proposals/settings`.
  Future<MaintenanceSettings> settings();

  /// Cierre de sesión: se descartan las claves de idempotencia en vuelo.
  void reset();

  /// `POST /driver/maintenance-proposals/:id/accept`.
  Future<MaintenanceProposal> accept(String proposalId);

  /// `POST /driver/maintenance-proposals/:id/reject`. [altStart] y [altEnd]
  /// (UTC) van juntos. 400 si la alternativa no es viable; 409 si la
  /// propuesta ya no está vigente.
  Future<MaintenanceProposal> reject(
    String proposalId, {
    required String reason,
    DateTime? altStart,
    DateTime? altEnd,
  });
}

class HttpMaintenanceRepository implements MaintenanceRepository {
  HttpMaintenanceRepository(
      {ApiClient? api, DriverAuthService? auth, Uuid? uuid})
      : _api = api ?? ApiClient(),
        _authOverride = auth,
        _uuid = uuid ?? const Uuid();

  static String get basePath =>
      '${AppConfig.apiV2Url}driver/maintenance-proposals';
  static String get settingsPath => '$basePath/settings';
  static String acceptPath(String id) => '$basePath/$id/accept';
  static String rejectPath(String id) => '$basePath/$id/reject';

  final ApiClient _api;
  final DriverAuthService? _authOverride;
  final Uuid _uuid;
  final Map<String, String> _keys = {};

  DriverAuthService get _auth => _authOverride ?? locator<DriverAuthService>();

  String? _keysUser;

  @override
  void reset() {
    _keys.clear();
    _keysUser = null;
  }

  Future<String> _token() async {
    // Las claves son del chofer que las generó: con otro usuario no se reusan.
    final user = _auth.userId;
    if (_keysUser != user) _keys.clear();
    _keysUser = user;
    final t = await _auth.token;
    if (t == null) throw StateError('Sin sesión');
    return t;
  }

  static Map<String, dynamic> _map(Response r) =>
      Map<String, dynamic>.from(r.data as Map);

  /// La `Idempotency-Key` se reusa mientras no haya respuesta del back (red
  /// caída) para no duplicar la respuesta.
  Future<Response> _post(String path, Map<String, dynamic> body) async {
    final token = await _token();
    final id = '$path:${jsonEncode(body)}';
    final key = _keys.putIfAbsent(id, _uuid.v4);
    try {
      final r = await _api.post(path, body, token, {'Idempotency-Key': key});
      _keys.remove(id);
      return r;
    } catch (e) {
      if (!keepIdempotencyKey(e)) _keys.remove(id);
      rethrow;
    }
  }

  @override
  Future<MaintenancePage> proposals({int limit = 50, int offset = 0}) async =>
      MaintenancePage.fromJson(_map(await _api.get(
          '$basePath?limit=$limit&offset=$offset', await _token())));

  @override
  Future<MaintenanceSettings> settings() async => MaintenanceSettings.fromJson(
      _map(await _api.get(settingsPath, await _token())));

  @override
  Future<MaintenanceProposal> accept(String proposalId) async =>
      MaintenanceProposal.fromJson(
          _map(await _post(acceptPath(proposalId), const {})));

  @override
  Future<MaintenanceProposal> reject(
    String proposalId, {
    required String reason,
    DateTime? altStart,
    DateTime? altEnd,
  }) async =>
      MaintenanceProposal.fromJson(_map(await _post(rejectPath(proposalId), {
        'reason': reason.trim(),
        if (altStart != null && altEnd != null)
          'alternative': {
            'start': altStart.toUtc().toIso8601String(),
            'end': altEnd.toUtc().toIso8601String(),
          },
      })));
}
