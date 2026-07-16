import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:driver_mobile/app/app.locator.dart';
import 'package:driver_mobile/app/app.router.dart';
import 'package:driver_mobile/services/driver_auth_service.dart';
import 'package:driver_mobile/services/fcm_service.dart';
import 'package:stacked_services/stacked_services.dart';

class StartupViewModel extends BaseViewModel {
  final _navigationService = locator<NavigationService>();
  final _authService = locator<DriverAuthService>();
  final _fcmService = locator<FcmService>();

  /// Decide adónde ir según haya o no una sesión de chofer válida. Si Firebase
  /// tiene sesión y restauramos el user_id, va directo a Home; si no, a Login.
  Future runStartupLogic() async {
    final restored = await _authService.restoreSession();

    if (restored) {
      // Best-effort: re-registra (o renueva) el token FCM en cada apertura de
      // la app con sesión activa, sin bloquear la navegación a Home.
      unawaited(_fcmService.registerForCurrentUser(_authService));
      await _navigationService.replaceWithHomeView();
    } else {
      await _navigationService.replaceWithLoginView();
    }
  }
}
