import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/fcm_service.dart';
import 'package:splg_driver/ui/views/login/login_view.form.dart';

class LoginViewModel extends FormViewModel {
  final _navigationService = locator<NavigationService>();
  final _authService = locator<DriverAuthService>();
  final _fcmService = locator<FcmService>();

  /// Mensaje de error para mostrar bajo el formulario (null = sin error).
  String? errorMessage;

  bool showPassword = false;

  void togglePasswordVisibility() {
    showPassword = !showPassword;
    notifyListeners();
  }

  /// Abre la pantalla de recuperación con el email que ya escribió.
  Future<void> onForgotPassword() async {
    if (isBusy) return;
    final email = emailValue?.trim();
    await _navigationService.navigateToForgotPasswordView(
      email: (email == null || email.isEmpty) ? null : email,
    );
  }

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
      // Best-effort, no bloquea la navegación: registra el token FCM del
      // chofer para poder recibir ofertas de pedido con la app cerrada.
      unawaited(_fcmService.registerForCurrentUser(_authService));
      _navigationService.replaceWithHomeView();
    } else {
      errorMessage = 'No pudimos iniciar sesión. Revisá tus datos.';
      notifyListeners();
    }
  }
}
