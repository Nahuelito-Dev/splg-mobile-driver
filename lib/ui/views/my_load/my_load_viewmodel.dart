import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/truck_load.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

/// Mi carga, sólo lectura: la carga del camión abierta del chofer
/// (`GET /truck-loads/mine`). La abre y la rinde el administrador en el panel.
class MyLoadViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();

  MyTruckLoad? data;

  /// Motivo del último pull-to-refresh fallido (se sigue viendo lo anterior).
  String? refreshError;

  TruckLoad? get openLoad => data?.load;
  bool get requiresOpenLoad => data?.requireOpenTruckLoad ?? false;

  @override
  Future<void> fetch() async {
    data = await _api.myTruckLoad();
    refreshError = null;
  }

  /// Pull-to-refresh: relee sin tapar la pantalla con el indicador de carga.
  Future<void> refresh() async {
    try {
      await fetch();
      loadError = null;
    } catch (e) {
      refreshError = DriverApiService.errorMessage(e);
    }
    notifyListeners();
  }
}
