import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/order_history.dart';
import 'package:splg_driver/services/driver_api_service.dart';

/// Una parte del detalle que se lee aparte del pedido: cargando, con error o
/// con datos.
class DetailSection<T> {
  bool loading = true;
  String? error;
  List<T> items = const [];

  bool get isEmpty => !loading && error == null && items.isEmpty;
}

/// Detalle de una entrega del historial. El pedido ya viene completo de la
/// lista; las incidencias y el historial de estados se leen del back, cada uno
/// por su cuenta: si uno falla, el otro se ve igual y se reintenta solo.
class DeliveryDetailViewModel extends BaseViewModel {
  DeliveryDetailViewModel(this.order);

  final DriverOrder order;
  DriverApiService get _api => locator<DriverApiService>();

  final incidents = DetailSection<OrderIncident>();
  final history = DetailSection<StatusChange>();
  bool _disposed = false;

  Future<void> load() => Future.wait([loadIncidents(), loadHistory()]);

  Future<void> loadIncidents() =>
      _read(incidents, () => _api.orderIncidents(order.id));

  Future<void> loadHistory() =>
      _read(history, () => _api.orderStatusHistory(order.id));

  Future<void> _read<T>(
      DetailSection<T> s, Future<List<T>> Function() read) async {
    s.loading = true;
    s.error = null;
    notifyListeners();
    try {
      s.items = await read();
    } catch (e) {
      s.error = actionErrorText(e,
          fallback: 'No pudimos cargar los datos. Probá de nuevo.');
    }
    s.loading = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
