import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:splg_driver/ui/views/change_password/change_password_viewmodel.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

void main() {
  late MockDriverAuthService auth;

  setUp(() {
    registerServices();
    auth = locator<DriverAuthService>() as MockDriverAuthService;
  });
  tearDown(() => locator.reset());

  ChangePasswordViewModel filled({
    String current = 'Actual123',
    String next = 'Nueva1234',
    String repeat = 'Nueva1234',
  }) =>
      ChangePasswordViewModel()
        ..onCurrentChanged(current)
        ..onNextChanged(next)
        ..onRepeatChanged(repeat);

  test('"Olvidé mi contraseña" abre recuperar con el email de la cuenta',
      () async {
    when(auth.email).thenReturn('chofer@splg.com');
    final nav = locator<NavigationService>() as MockNavigationService;

    await ChangePasswordViewModel().forgotPassword();

    verify(nav.navigateToForgotPasswordView(email: 'chofer@splg.com'))
        .called(1);
  });

  group('validación', () {
    test('la política pide 8 caracteres, mayúscula y número', () {
      expect(ChangePasswordViewModel.meetsPolicy('Nueva1234'), isTrue);
      expect(ChangePasswordViewModel.meetsPolicy('nueva1234'), isFalse);
      expect(ChangePasswordViewModel.meetsPolicy('Nueva'), isFalse);
      expect(ChangePasswordViewModel.meetsPolicy('NuevaClave'), isFalse);
    });

    test('vacío es neutro, válido es verde, inválido es rojo', () {
      final m = ChangePasswordViewModel();
      expect(m.nextState, FieldState.neutral);
      m.onNextChanged('corta');
      expect(m.nextState, FieldState.invalid);
      expect(m.nextError, isNotNull);
      m.onNextChanged('Nueva1234');
      expect(m.nextState, FieldState.valid);
    });

    test('repetir distinto marca "no coinciden"', () {
      final m = filled(repeat: 'Otra1234');
      expect(m.repeatState, FieldState.invalid);
      expect(m.repeatError, 'Las contraseñas no coinciden');
      expect(m.canSubmit, isFalse);
    });

    test('con todo válido se puede confirmar', () {
      expect(filled().canSubmit, isTrue);
      expect(filled(current: '').canSubmit, isFalse);
    });
  });

  group('submit', () {
    test('éxito: pide el cambio y queda hecho', () async {
      when(auth.changePassword('Actual123', 'Nueva1234'))
          .thenAnswer((_) async => PasswordChangeResult.ok);
      final m = filled();

      await m.submit();

      expect(m.done, isTrue);
      expect(m.generalError, isNull);
    });

    test('contraseña actual mal: campo en rojo, no termina', () async {
      when(auth.changePassword(any, any))
          .thenAnswer((_) async => PasswordChangeResult.wrongCurrent);
      final m = filled();

      await m.submit();

      expect(m.done, isFalse);
      expect(m.currentState, FieldState.invalid);
      expect(m.currentError, 'Contraseña incorrecta');
      m.onCurrentChanged('Otra1234');
      expect(m.currentState, FieldState.neutral);
    });

    test('sin red y otros errores muestran el aviso general', () async {
      when(auth.changePassword(any, any))
          .thenAnswer((_) async => PasswordChangeResult.network);
      final m = filled();
      await m.submit();
      expect(m.generalError, contains('Sin conexión'));
      expect(m.done, isFalse);

      when(auth.changePassword(any, any))
          .thenAnswer((_) async => PasswordChangeResult.tooManyRequests);
      await m.submit();
      expect(m.generalError, contains('Demasiados intentos'));
    });

    test('si el servicio lanza, la pantalla no queda girando', () async {
      when(auth.changePassword(any, any)).thenThrow(StateError('plugin'));
      final m = filled();

      await m.submit();

      expect(m.isBusy, isFalse);
      expect(m.done, isFalse);
      expect(m.generalError, contains('No pudimos cambiar'));
    });

    test('Firebase pide más requisitos: mensaje claro', () async {
      when(auth.changePassword(any, any))
          .thenAnswer((_) async => PasswordChangeResult.notMeetsRequirements);
      final m = filled();

      await m.submit();

      expect(m.isBusy, isFalse);
      expect(m.generalError, contains('requisitos de seguridad'));
    });

    test('la nueva no puede ser igual a la actual', () async {
      final m =
          filled(current: 'Misma1234', next: 'Misma1234', repeat: 'Misma1234');
      expect(m.nextState, FieldState.invalid);
      expect(m.nextError, contains('igual a la actual'));
      expect(m.canSubmit, isFalse);
      await m.submit();
      verifyNever(auth.changePassword(any, any));
    });

    test('con datos inválidos no llama al servicio', () async {
      await filled(repeat: 'x').submit();
      verifyNever(auth.changePassword(any, any));
    });
  });
}
