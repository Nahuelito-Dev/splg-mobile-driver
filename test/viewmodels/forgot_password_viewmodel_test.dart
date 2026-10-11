import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/ui/views/forgot_password/forgot_password_viewmodel.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

void main() {
  late MockDriverAuthService auth;

  setUp(() {
    registerServices();
    auth = locator<DriverAuthService>() as MockDriverAuthService;
  });
  tearDown(() => locator.reset());

  test('email inválido: avisa y no llama al servicio', () async {
    final m = ForgotPasswordViewModel(initialEmail: 'no-es-mail');
    await m.submit();
    verifyNever(auth.sendPasswordResetEmail(any));
    expect(m.errorMessage, 'Ingresá un email válido.');
    expect(m.sent, isFalse);
  });

  test('email válido: pide el mail y pasa a "enviado"', () async {
    when(auth.sendPasswordResetEmail('a@b.com')).thenAnswer((_) async => true);
    final m = ForgotPasswordViewModel(initialEmail: 'a@b.com');
    await m.submit();
    verify(auth.sendPasswordResetEmail('a@b.com')).called(1);
    expect(m.sent, isTrue);
    expect(m.isBusy, isFalse);
  });

  test('si falla muestra el error y no pasa a "enviado"', () async {
    when(auth.sendPasswordResetEmail(any)).thenAnswer((_) async => false);
    final m = ForgotPasswordViewModel(initialEmail: 'a@b.com');
    await m.submit();
    expect(m.sent, isFalse);
    expect(m.errorMessage, contains('No pudimos enviar'));
  });

  test('escribir limpia el error', () async {
    final m = ForgotPasswordViewModel();
    await m.submit();
    m.onEmailChanged('a@b.com');
    expect(m.errorMessage, isNull);
  });
}
