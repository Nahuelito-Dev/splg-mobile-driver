import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Estado de un campo del formulario.
enum FieldState { neutral, valid, invalid }

class ChangePasswordViewModel extends BaseViewModel {
  final _auth = locator<DriverAuthService>();
  final _nav = locator<NavigationService>();

  /// "Olvidé mi contraseña": lleva a recuperarla con el email de la cuenta.
  Future<void> forgotPassword() =>
      _nav.navigateToForgotPasswordView(email: _auth.email);

  String _current = '';
  String _next = '';
  String _repeat = '';

  /// Error que devolvió el servidor para la contraseña actual.
  bool _currentRejected = false;

  /// Mensaje general (red, demasiados intentos, etc.).
  String? generalError;

  /// true cuando la contraseña se cambió.
  bool done = false;

  /// Mínimo 8 caracteres, una mayúscula y un número.
  static bool meetsPolicy(String p) =>
      p.length >= 8 &&
      RegExp(r'[A-Z]').hasMatch(p) &&
      RegExp(r'\d').hasMatch(p);

  void onCurrentChanged(String v) {
    _current = v;
    _currentRejected = false;
    generalError = null;
    notifyListeners();
  }

  void onNextChanged(String v) {
    _next = v;
    generalError = null;
    notifyListeners();
  }

  void onRepeatChanged(String v) {
    _repeat = v;
    generalError = null;
    notifyListeners();
  }

  FieldState get currentState =>
      _currentRejected ? FieldState.invalid : FieldState.neutral;
  String? get currentError => _currentRejected ? 'Contraseña incorrecta' : null;

  /// La nueva es igual a la actual (no tiene sentido cambiarla).
  bool get _sameAsCurrent => _next.isNotEmpty && _next == _current;

  FieldState get nextState => _next.isEmpty
      ? FieldState.neutral
      : (meetsPolicy(_next) && !_sameAsCurrent
          ? FieldState.valid
          : FieldState.invalid);
  String? get nextError => nextState != FieldState.invalid
      ? null
      : (_sameAsCurrent
          ? 'La nueva contraseña no puede ser igual a la actual.'
          : 'Usá al menos 8 caracteres, una mayúscula y un número.');

  FieldState get repeatState => _repeat.isEmpty
      ? FieldState.neutral
      : (_repeat == _next && nextState == FieldState.valid
          ? FieldState.valid
          : FieldState.invalid);
  String? get repeatError =>
      repeatState == FieldState.invalid ? 'Las contraseñas no coinciden' : null;

  bool get canSubmit =>
      !isBusy &&
      _current.isNotEmpty &&
      nextState == FieldState.valid &&
      repeatState == FieldState.valid;

  Future<void> submit() async {
    if (!canSubmit) return;
    generalError = null;
    setBusy(true);
    PasswordChangeResult result;
    try {
      result = await _auth.changePassword(_current, _next);
    } catch (_) {
      result = PasswordChangeResult.other;
    } finally {
      setBusy(false);
    }
    switch (result) {
      case PasswordChangeResult.ok:
        done = true;
      case PasswordChangeResult.wrongCurrent:
        _currentRejected = true;
      case PasswordChangeResult.weak:
        generalError = 'La nueva contraseña es demasiado débil.';
      case PasswordChangeResult.notMeetsRequirements:
        generalError = 'La nueva contraseña no cumple los requisitos de '
            'seguridad: usá al menos 8 caracteres, una mayúscula y un número.';
      case PasswordChangeResult.network:
        generalError = 'Sin conexión. Revisá tu internet y probá de nuevo.';
      case PasswordChangeResult.tooManyRequests:
        generalError = 'Demasiados intentos. Esperá unos minutos.';
      case PasswordChangeResult.other:
        generalError = 'No pudimos cambiar la contraseña. Probá de nuevo.';
    }
    notifyListeners();
  }
}
