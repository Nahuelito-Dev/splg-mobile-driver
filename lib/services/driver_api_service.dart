import 'package:dio/dio.dart';
import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/config/app_config.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/models/driver_ops.dart' show apiDay;
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/truck_load.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Lecturas del chofer contra el back: perfil, foto, vehículo, historial de
/// entregas y calificación. Cada método lanza si el back falla; la pantalla
/// muestra el error y ofrece reintentar.
class DriverApiService {
  DriverApiService({ApiClient? api, DriverAuthService? auth})
      : _api = api ?? ApiClient(),
        _authOverride = auth;

  final ApiClient _api;
  final DriverAuthService? _authOverride;

  DriverAuthService get _auth => _authOverride ?? locator<DriverAuthService>();

  DriverProfile? _profile;

  Future<String> _token() async {
    final t = await _auth.token;
    if (t == null) throw StateError('Sin sesión');
    return t;
  }

  /// `GET /users/:id`. Se cachea porque trae el `delivery_id` que piden las
  /// demás pantallas; `refresh` fuerza la lectura y si cambió el chofer se vuelve a leer.
  Future<DriverProfile> profile({bool refresh = false}) async {
    if (!refresh && _profile != null && _profile!.userId == _auth.userId) {
      return _profile!;
    }
    final id = _auth.userId;
    if (id == null) throw StateError('Sin sesión');
    final res = await _api.get('users/$id', await _token());
    _profile =
        DriverProfile.fromJson(Map<String, dynamic>.from(res.data as Map));
    return _profile!;
  }

  /// `GET /users/me/photo?modo=url`: URL firmada de S3, o null si no tiene foto.
  Future<String?> photoUrl() async {
    final res = await _api.get('users/me/photo?modo=url', await _token());
    final data = res.data;
    return data is Map ? data['url']?.toString() : null;
  }

  /// `GET /delivery/me/vehicle`: sin cuerpo si no tiene vehículo en uso.
  Future<DriverVehicle?> vehicle() async {
    final res = await _api.get('delivery/me/vehicle', await _token());
    final data = res.data;
    if (data is! Map || data.isEmpty) return null;
    return DriverVehicle.fromJson(Map<String, dynamic>.from(data));
  }

  /// `GET /truck-loads/mine`: la carga abierta del chofer (o `load` null) y si
  /// la distribuidora exige carga abierta para recibir pedidos.
  Future<MyTruckLoad> myTruckLoad() async {
    final res = await _api.get('truck-loads/mine', await _token());
    return MyTruckLoad.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// Por qué el chofer no recibe pedidos por su carga del camión (sin carga con
  /// el control D5, carga sin salir, ya devuelta, otro vehículo), o null si
  /// puede. Es el `message` que el back da en `GET /orders/available` cuando
  /// `openLoadRequired` es true; se pide una sola fila para no traer el pool.
  Future<String?> noOrdersReason() async {
    final res = await _api.get('orders/available?limit=1', await _token());
    final data = res.data;
    if (data is! Map || data['openLoadRequired'] != true) return null;
    final m = data['message']?.toString();
    return (m == null || m.isEmpty) ? null : m;
  }

  /// Tamaño de página con el que se recorre todo el historial (máximo del back).
  static const int maxPageSize = 100;

  /// Una página del historial: `GET /orders/delivery/:deliveryId?limit&offset`
  /// (del más nuevo al más viejo). `total` es el total real del chofer.
  Future<OrdersPage> ordersPage({int offset = 0, int limit = 20}) async {
    final p = await profile();
    final deliveryId = p.deliveryId;
    if (deliveryId == null) {
      return const OrdersPage(orders: [], total: 0, offset: 0);
    }
    final res = await _api.get(
        'orders/delivery/$deliveryId?limit=$limit&offset=$offset',
        await _token());
    final data = res.data as Map;
    final list = data['orders'] as List? ?? const [];
    final orders = [
      for (final o in list.whereType<Map>())
        DriverOrder.fromJson(Map<String, dynamic>.from(o)),
    ];
    final total = data['total'];
    return OrdersPage(
      orders: orders,
      total: total is num ? total.toInt() : offset + orders.length,
      offset: offset,
    );
  }

  /// `GET /api/v2/reports/delivery/me/daily-totals`: por día, los pedidos
  /// entregados y lo que había que cobrar de ellos, sumado por el back.
  Future<List<DayTotal>> dailyTotals(
      {required DateTime from, required DateTime to}) async {
    final res = await _api.get(
        '${AppConfig.apiV2Url}reports/delivery/me/daily-totals'
        '?from=${apiDay(from)}&to=${apiDay(to)}',
        await _token());
    final data = res.data;
    return [
      if (data is List)
        for (final d in data.whereType<Map>())
          DayTotal.fromJson(Map<String, dynamic>.from(d)),
    ];
  }

  /// `GET /orders/delivery/me/active`: el pedido en curso del chofer sin
  /// importar cuándo se creó (en camino; si no, el aceptado más antiguo; si no,
  /// el entregado hoy en efectivo con el cobro pendiente). `204` => null.
  Future<DriverOrder?> activeOrder() async {
    final res = await _api.get('orders/delivery/me/active', await _token());
    final data = res.data;
    if (res.statusCode == 204 || data is! Map || data.isEmpty) return null;
    return DriverOrder.fromJson(Map<String, dynamic>.from(data));
  }

  /// Todo el historial: recorre las páginas hasta llegar al `total` del back.
  Future<List<DriverOrder>> orders() async {
    final all = <DriverOrder>[];
    var page = await ordersPage(limit: maxPageSize);
    all.addAll(page.orders);
    while (page.hasMore) {
      page = await ordersPage(offset: page.nextOffset, limit: maxPageSize);
      all.addAll(page.orders);
    }
    return all;
  }

  /// `GET /ratings/user/:userId/summary`.
  Future<RatingSummary> rating() async {
    final p = await profile();
    final res =
        await _api.get('ratings/user/${p.userId}/summary', await _token());
    return RatingSummary.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// Texto para mostrar cuando una lectura falla: el mensaje del back sólo si
  /// es un 400/409 de negocio en castellano; si no, un texto propio por código.
  static String errorMessage(Object e) {
    if (e is DioException) {
      return ApiErrorText.of(e.response?.statusCode, e.response?.data);
    }
    return 'No pudimos cargar los datos. Probá de nuevo.';
  }
}
