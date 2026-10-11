import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/ui/views/login/login_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

void main() {
  group('LoginViewModel Tests -', () {
    late MockDriverAuthService auth;

    setUp(() {
      registerServices();
      auth = locator<DriverAuthService>() as MockDriverAuthService;
    });
    tearDown(() => locator.reset());

    LoginViewModel withEmail(String email) =>
        LoginViewModel()..formValueMap['email'] = email;

    group('onForgotPassword -', () {
      test('abre la recuperación con el email escrito', () async {
        final nav = locator<NavigationService>() as MockNavigationService;

        await withEmail('a@b.com').onForgotPassword();

        verify(nav.navigateToForgotPasswordView(email: 'a@b.com')).called(1);
        verifyNever(auth.sendPasswordResetEmail(any));
      });

      test('sin email abre la recuperación vacía', () async {
        final nav = locator<NavigationService>() as MockNavigationService;

        await LoginViewModel().onForgotPassword();

        verify(nav.navigateToForgotPasswordView(email: null)).called(1);
      });
    });

    test('togglePasswordVisibility alterna la contraseña visible', () {
      final model = LoginViewModel();
      expect(model.showPassword, isFalse);
      model.togglePasswordVisibility();
      expect(model.showPassword, isTrue);
    });

    group('onLogin -', () {
      test('sin datos pide email y contraseña', () async {
        final model = LoginViewModel();

        await model.onLogin();

        verifyNever(auth.signIn(any, any));
        expect(model.errorMessage, 'Ingresá tu email y contraseña.');
      });

      test('credenciales rechazadas muestran el aviso y no navegan', () async {
        when(auth.signIn(any, any)).thenAnswer((_) async => false);
        final model = withEmail('a@b.com')..formValueMap['password'] = 'mala';

        await model.onLogin();

        expect(
            model.errorMessage, 'No pudimos iniciar sesión. Revisá tus datos.');
      });
    });
  });
}
