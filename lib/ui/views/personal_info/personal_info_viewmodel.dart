import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

class PersonalInfoViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();

  DriverProfile? profile;

  @override
  Future<void> fetch() async {
    profile = await _api.profile();
  }
}
