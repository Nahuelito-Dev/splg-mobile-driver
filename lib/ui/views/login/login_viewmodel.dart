import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:driver_mobile/app/app.router.dart';
import 'package:driver_mobile/app/app.locator.dart';

class LoginViewModel extends FormViewModel {
  final _navigationService = locator<NavigationService>();

  Future<void> onLogin() async {
    setBusy(true);
    await Future.delayed(const Duration(seconds: 3));
    _navigationService.replaceWithHomeView();
    setBusy(false);
  }
}
