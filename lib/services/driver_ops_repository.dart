import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Lo que el chofer hace en el día además de entregar. Las pantallas programan
/// contra esta interfaz; las rutas y los cuerpos viven en
/// [HttpDriverOpsRepository].
abstract class DriverOpsRepository {
  /// Última jornada abierta que se leyó o marcó en esta sesión; null si no hay.
  Workday? get workday;

  /// `GET /attendance/mine/current`: la jornada abierta (también la de un día
  /// anterior sin cerrar) o null si no tiene (204).
  Future<Workday?> currentWorkday();

  /// `POST /attendance/mine/check-in`: abre la jornada o devuelve la abierta de hoy.
  Future<Workday> checkIn();

  /// `POST /attendance/mine/check-out`.
  Future<Workday> checkOut();

  /// `GET /driver-settlements/mine`: la rendición del día (la abre si no existe).
  Future<Settlement> mySettlement({DateTime? date});

  /// Categorías de egreso que el chofer puede elegir (activas y no de sistema).
  Future<List<ExpenseCategory>> expenseCategories();

  /// `POST /driver-settlements/:id/submit`.
  Future<Settlement> submitSettlement(
    String settlementId, {
    required num declaredCash,
    List<ExpenseInput> expenses = const [],
    String? notes,
    String? idempotencyKey,
  });

  /// `GET /commissions/mine?from&to`.
  Future<MyCommissions> myCommissions(DateTime from, DateTime to);

  /// `POST /fleet/fuel-loads/mine`.
  Future<FuelLoadRecord> registerFuelLoad(FuelLoadInput input,
      {String? idempotencyKey});

  /// `POST /fleet/accidents/mine`.
  Future<AccidentRecord> reportAccident(AccidentInput input,
      {String? idempotencyKey});
}

/// Implementación contra el back. Cada intención usa una `Idempotency-Key`
/// (según la acción y el cuerpo), reusada mientras no haya respuesta del back
/// (red caída) para no duplicar el alta.
class HttpDriverOpsRepository implements DriverOpsRepository {
  HttpDriverOpsRepository({
    ApiClient? api,
    DriverAuthService? auth,
    Uuid? uuid,
  })  : _api = api ?? ApiClient(),
        _authOverride = auth,
        _uuid = uuid ?? const Uuid();

  static const checkInPath = 'attendance/mine/check-in';
  static const checkOutPath = 'attendance/mine/check-out';
  static const currentPath = 'attendance/mine/current';
  static const settlementPath = 'driver-settlements/mine';
  static const categoriesPath = 'cash-categories?direction=expense&limit=100';
  static const fuelPath = 'fleet/fuel-loads/mine';
  static const accidentPath = 'fleet/accidents/mine';
  static String submitPath(String id) => 'driver-settlements/$id/submit';
  static String commissionsPath(DateTime from, DateTime to) =>
      'commissions/mine?from=${apiDay(from)}&to=${apiDay(to)}&limit=100';

  final ApiClient _api;
  final DriverAuthService? _authOverride;
  final Uuid _uuid;
  final Map<String, String> _keys = {};

  Workday? _workday;
  String? _workdayUser;

  /// La jornada es de quien marcó: si cambió la sesión, no se arrastra.
  @override
  Workday? get workday => _workdayUser == _auth.userId ? _workday : null;

  Workday _remember(Workday w) {
    _workdayUser = _auth.userId;
    return _workday = w;
  }

  DriverAuthService get _auth => _authOverride ?? locator<DriverAuthService>();

  Future<String> _token() async {
    final t = await _auth.token;
    if (t == null) throw StateError('Sin sesión');
    return t;
  }

  /// [idempotencyKey]: la clave de la intención, que fija quien llama (la
  /// pantalla) para reintentar el mismo envío; sin ella se deriva de la ruta y
  /// el cuerpo.
  Future<Response> _post(String path, Map<String, dynamic> body,
      {String? idempotencyKey}) async {
    final id = '$path:${jsonEncode(body)}';
    final key = idempotencyKey ?? _keys.putIfAbsent(id, _uuid.v4);
    try {
      final r =
          await _api.post(path, body, await _token(), {'Idempotency-Key': key});
      _keys.remove(id);
      return r;
    } catch (e) {
      // Con un rechazo de negocio la clave se descarta; sin respuesta, 5xx, 429,
      // 409 "en curso" o 422 de clave ya usada se conserva para no duplicar.
      if (!keepIdempotencyKey(e)) _keys.remove(id);
      rethrow;
    }
  }

  static Map<String, dynamic> _map(Response r) =>
      Map<String, dynamic>.from(r.data as Map);

  @override
  Future<Workday?> currentWorkday() async {
    final r = await _api.get(currentPath, await _token());
    final data = r.data;
    final w = (r.statusCode == 204 || data is! Map || data.isEmpty)
        ? null
        : Workday.fromJson(Map<String, dynamic>.from(data));
    _workdayUser = _auth.userId;
    return _workday = w;
  }

  @override
  Future<Workday> checkIn() async =>
      _remember(Workday.fromJson(_map(await _post(checkInPath, const {}))));

  @override
  Future<Workday> checkOut() async =>
      _remember(Workday.fromJson(_map(await _post(checkOutPath, const {}))));

  @override
  Future<Settlement> mySettlement({DateTime? date}) async {
    final path =
        date == null ? settlementPath : '$settlementPath?date=${apiDay(date)}';
    return Settlement.fromJson(_map(await _api.get(path, await _token())));
  }

  @override
  Future<List<ExpenseCategory>> expenseCategories() async {
    try {
      final r = await _api.get(categoriesPath, await _token());
      final data = r.data;
      final list = data is Map ? data['data'] : null;
      return [
        if (list is List)
          for (final c in list.whereType<Map>())
            ExpenseCategory.fromJson(Map<String, dynamic>.from(c)),
      ].where((c) => c.selectable).toList();
    } on DioException {
      // Sin categorías no se declaran gastos; el efectivo se rinde igual.
      return const [];
    }
  }

  @override
  Future<Settlement> submitSettlement(
    String settlementId, {
    required num declaredCash,
    List<ExpenseInput> expenses = const [],
    String? notes,
    String? idempotencyKey,
  }) async {
    final n = notes?.trim();
    final r = await _post(
        submitPath(settlementId),
        {
          'declaredCash': declaredCash,
          if (expenses.isNotEmpty)
            'expenses': [for (final e in expenses) e.toJson()],
          if (n != null && n.isNotEmpty) 'notes': n,
        },
        idempotencyKey: idempotencyKey);
    return Settlement.fromJson(_map(r));
  }

  @override
  Future<MyCommissions> myCommissions(DateTime from, DateTime to) async =>
      MyCommissions.fromJson(
          _map(await _api.get(commissionsPath(from, to), await _token())));

  @override
  Future<FuelLoadRecord> registerFuelLoad(FuelLoadInput input,
          {String? idempotencyKey}) async =>
      FuelLoadRecord.fromJson(_map(await _post(fuelPath, input.toJson(),
          idempotencyKey: idempotencyKey)));

  @override
  Future<AccidentRecord> reportAccident(AccidentInput input,
          {String? idempotencyKey}) async =>
      AccidentRecord.fromJson(_map(await _post(accidentPath, input.toJson(),
          idempotencyKey: idempotencyKey)));
}
