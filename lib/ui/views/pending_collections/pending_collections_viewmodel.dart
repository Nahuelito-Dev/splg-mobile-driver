import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

/// Pedidos entregados en efectivo cuyo cobro todavía no se registró (ni como
/// cobrado ni como impago). Se arma con el historial del chofer.
class PendingCollectionsViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();
  final _nav = locator<NavigationService>();

  List<DriverOrder> orders = const [];
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Future<void> fetch() async {
    final all = await _api.orders();
    orders = [
      for (final o in all)
        if (o.isCashCollectionPending) o,
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Abre la pantalla de cobro del pedido y, al volver, relee la lista.
  Future<void> open(DriverOrder order) async {
    await _nav.navigateToPaymentView(orderId: order.id);
    if (_disposed) return;
    await load();
  }
}
