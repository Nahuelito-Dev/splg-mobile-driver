import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:driver_mobile/app/app.router.dart';
import 'package:driver_mobile/app/app.locator.dart';
import 'package:driver_mobile/services/driver_auth_service.dart';
import 'package:driver_mobile/ui/views/login/login_view.form.dart';

class LoginViewModel extends FormViewModel {
  final _navigationService = locator<NavigationService>();
  final _authService = locator<DriverAuthService>();

  /// Mensaje de error para mostrar bajo el formulario (null = sin error).
  String? errorMessage;

  Future<void> onLogin() async {
    if (isBusy) return;
    errorMessage = null;

    final email = emailValue?.trim() ?? '';
    final password = passwordValue ?? '';
    if (email.isEmpty || password.isEmpty) {
      errorMessage = 'Ingresá tu email y contraseña.';
      notifyListeners();
      return;
    }

    setBusy(true);
    final ok = await _authService.signIn(email, password);
    setBusy(false);

    if (ok) {
      _navigationService.replaceWithHomeView();
    } else {
      errorMessage = 'No pudimos iniciar sesión. Revisá tus datos.';
      notifyListeners();
    }
  }
}
