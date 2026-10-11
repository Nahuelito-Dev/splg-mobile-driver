import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';

class WelcomeViewModel extends BaseViewModel {
  final _nav = locator<NavigationService>();

  Future<void> goToLogin() => _nav.navigateToLoginView();
}
