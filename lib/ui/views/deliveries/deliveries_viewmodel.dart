import 'package:flutter/foundation.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
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
