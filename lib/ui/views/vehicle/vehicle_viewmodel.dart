import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

class VehicleViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();

  /// null: la distribuidora no le asignó vehículo.
  DriverVehicle? vehicle;

  @override
  Future<void> fetch() async {
    vehicle = await _api.vehicle();
  }
}
