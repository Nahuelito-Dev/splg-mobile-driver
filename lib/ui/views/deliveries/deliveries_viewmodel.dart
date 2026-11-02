import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/driver_ops.dart' show apiDay;
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

/// Historial de entregas con paginación: trae la primera página y el resto
/// a medida que se baja (`GET /orders/delivery/:id?limit&offset`).
class DeliveriesViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();
  final _nav = locator<NavigationService>();

  static const pageSize = 20;

  List<DriverOrder> orders = const [];

  /// Total de pedidos del chofer según el back.
  int total = 0;

  /// Lo entregado por día y lo que había que cobrar, que suma el back
  /// (clave `YYYY-MM-DD`). Si no se pudo leer, la lista sigue sin los totales.
  Map<String, DayTotal> dayTotals = const {};

  /// El total cobrado de [day] ya formateado, o null si ese día no tiene
  /// entregas o el back no lo informó.
  String? dayTotalLabel(DateTime day) {
    final t = dayTotals[apiDay(day)];
    return t == null ? null : formatMoney(t.totalAmount);
  }

  bool loadingMore = false;

  /// Falló la última carga de más (se puede reintentar con [loadMore]).
  String? moreError;

  /// Próximo `offset` que pide el back (no la cantidad de pedidos ya
  /// deduplicados: con un hueco o un repetido la lista no se traba).
  int _nextOffset = 0;

  /// Época de la lista: `load()` la incrementa y las respuestas de un
  /// `loadMore` de una época vieja se descartan.
  int _epoch = 0;

  bool get hasMore => _nextOffset < total && _lastPageHadItems;
  bool _lastPageHadItems = true;

  @override
  Future<void> fetch() async {
    final epoch = ++_epoch;
    final page = await _api.ordersPage(limit: pageSize);
    if (epoch != _epoch) return;
    orders = page.orders;
    total = page.total;
    _nextOffset = page.nextOffset;
    _lastPageHadItems = page.orders.isNotEmpty;
    moreError = null;
    loadingMore = false;
    _refreshDayTotals(epoch);
  }

  bool _closed = false;

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  /// Los totales por día llegan aparte: no demoran la lista ni la carga de la
  /// página siguiente. Al llegar se redibuja.
  void _refreshDayTotals(int epoch) {
    unawaited(_loadDayTotals(epoch).then((_) {
      if (!_closed && epoch == _epoch) notifyListeners();
    }));
  }

  /// Pide al back los totales de los días que cubre la lista cargada: desde el
  /// pedido más viejo hasta el más nuevo.
  Future<void> _loadDayTotals(int epoch) async {
    if (orders.isEmpty) return;
    var from = orders.first.date, to = orders.first.date;
    for (final o in orders) {
      if (o.date.isBefore(from)) from = o.date;
      if (o.date.isAfter(to)) to = o.date;
    }
    try {
      final totals = await _api.dailyTotals(from: from, to: to);
      if (epoch != _epoch) return;
      dayTotals = {for (final t in totals) t.day: t};
    } catch (e) {
      debugPrint('No se pudieron traer los totales por día: $e');
    }
  }

  /// Trae la página siguiente y la agrega (sin repetir pedidos). Tras un error
  /// no se reintenta sola (por scroll): sólo con `retry: true` ("Reintentar").
  Future<void> loadMore({bool retry = false}) async {
    if (loadingMore || !hasMore || isBusy) return;
    if (moreError != null && !retry) return;
    final epoch = _epoch;
    loadingMore = true;
    moreError = null;
    notifyListeners();
    try {
      final page = await _api.ordersPage(offset: _nextOffset, limit: pageSize);
      if (epoch != _epoch) return;
      final known = {for (final o in orders) o.id};
      orders = [...orders, ...page.orders.where((o) => !known.contains(o.id))];
      total = page.total;
      _nextOffset = page.nextOffset;
      _lastPageHadItems = page.orders.isNotEmpty;
      _refreshDayTotals(epoch);
    } catch (e) {
      if (epoch != _epoch) return;
      debugPrint('No se pudo traer más entregas: $e');
      moreError = DriverApiService.errorMessage(e);
    }
    loadingMore = false;
    notifyListeners();
  }

  Future<void> open(DriverOrder order) =>
      _nav.navigateToDeliveryDetailView(order: order);
}
