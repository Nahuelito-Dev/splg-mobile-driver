import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

/// Totales del chofer calculados con TODO su historial de entregas
/// (`GET /orders/delivery/:id`, paginado hasta el `total` del back): el back no
/// tiene un endpoint de estadísticas para choferes (`/orders/stats/*` es sólo
/// de administradores).
class EarningsViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();

  /// Reloj inyectable para los tests.
  DateTime Function() now = DateTime.now;

  EarningsSummary? summary;

  /// Filtro de los chips: 0 mes, 1 semana (últimos 7 días), 2 ayer, 3 hoy.
  int period = 3;

  void selectPeriod(int value) {
    period = value;
    notifyListeners();
  }

  @override
  Future<void> fetch() async {
    summary = EarningsSummary.from(await _api.orders(), now());
  }
}
