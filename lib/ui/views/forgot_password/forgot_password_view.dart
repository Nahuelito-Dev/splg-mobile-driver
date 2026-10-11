import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'forgot_password_viewmodel.dart';

class ForgotPasswordView extends StackedView<ForgotPasswordViewModel> {
  const ForgotPasswordView({super.key, this.email});

  /// Email ya escrito en el login, para no pedirlo de nuevo.
  final String? email;

  @override
  ForgotPasswordViewModel viewModelBuilder(BuildContext context) =>
      ForgotPasswordViewModel(initialEmail: email);

  @override
  Widget builder(
      BuildContext context, ForgotPasswordViewModel model, Widget? child) {
    final type = SplgType.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, context.sp(30), 20, 20),
              child: Column(
                children: [
                  (model.sent
                          ? SplgIllustration.mailSent
                          : SplgIllustration.recoverPassword)
                      .image(height: context.sp(105)),
                  SizedBox(height: context.sp(22)),
                  Text(
                    model.sent ? 'REVISÁ TU CORREO' : 'RECUPERAR CONTRASEÑA',
                    textAlign: TextAlign.center,
                    style: type.title.copyWith(fontSize: context.sp(14)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    model.sent
                        ? 'Si ${model.email.trim()} tiene una cuenta, te '
                            'mandamos un enlace para elegir una nueva '
                            'contraseña.'
                        : 'Ingresá la dirección de email a donde se enviará '
                            'el enlace para recuperar la contraseña.',
                    textAlign: TextAlign.center,
                    style: type.body.copyWith(color: context.brasa.muted),
                  ),
                  const SizedBox(height: 28),
                  if (!model.sent) ...[
                    SplgTextField(
                      key: const Key('forgot-email'),
                      controller: model.controller,
                      enabled: !model.isBusy,
                      hint: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      errorText: model.errorMessage,
                      onChanged: model.onEmailChanged,
                      onSubmitted: (_) => model.submit(),
                    ),
                    SizedBox(height: context.sp(70)),
                    SplgButton(
                      title: 'Enviar',
                      loading: model.isBusy,
                      onPressed: model.submit,
                    ),
                  ] else ...[
                    SizedBox(height: context.sp(40)),
                    SplgButton(
                      title: 'Volver al inicio de sesión',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                tooltip: 'Volver',
                icon: Icon(SplgIcons.back,
                    size: 24, color: context.brasa.primaryStrong),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
