import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked/stacked_annotations.dart';

import 'package:splg_driver/ui/common/app_strings.dart';

import 'login_view.form.dart';
import 'login_viewmodel.dart';

@FormView(
  fields: [
    FormTextField(name: 'email'),
    FormTextField(name: 'password'),
  ],
)
class LoginView extends StackedView<LoginViewModel> with $LoginView {
  const LoginView({super.key});

  @override
  Widget builder(
    BuildContext context,
    LoginViewModel viewModel,
    Widget? child,
  ) {
    final type = SplgType.of(context);
    final hasError = viewModel.errorMessage != null;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) viewModel.goBackToWelcome();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    key: const Key('login-back'),
                    tooltip: 'Volver',
                    icon: Icon(
                      SplgIcons.back,
                      size: 24,
                      color: context.brasa.primaryStrong,
                    ),
                    onPressed:
                        viewModel.isBusy ? null : viewModel.goBackToWelcome,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            top: context.sp(14),
                            bottom: context.sp(10),
                          ),
                          child: Center(
                            child: SplgIllustration.mailSent.image(
                              height: context.sp(150),
                            ),
                          ),
                        ),
                        Text(
                          '¡Hola!',
                          style: type.title.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: context.sp(18),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SplgTextField(
                          controller: emailController,
                          focusNode: emailFocusNode,
                          enabled: !viewModel.isBusy,
                          hint: loginViewHintEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                        ),
                        const SizedBox(height: 15),
                        SplgTextField(
                          controller: passwordController,
                          focusNode: passwordFocusNode,
                          enabled: !viewModel.isBusy,
                          hint: loginViewHintPassword,
                          obscure: !viewModel.showPassword,
                          textInputAction: TextInputAction.done,
                          suffixIcon: IconButton(
                            tooltip: viewModel.showPassword
                                ? 'Ocultar contraseña'
                                : 'Mostrar contraseña',
                            icon: Icon(
                              viewModel.showPassword
                                  ? SplgIcons.eyeOff
                                  : SplgIcons.eye,
                              size: 22,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: viewModel.togglePasswordVisibility,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: viewModel.isBusy
                                ? null
                                : viewModel.onForgotPassword,
                            child: Text(
                              loginForgotPassword,
                              style: type.captionStrong.copyWith(
                                fontSize: context.sp(10),
                              ),
                            ),
                          ),
                        ),
                        if (hasError)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              viewModel.errorMessage!,
                              textAlign: TextAlign.center,
                              style: type.body.copyWith(
                                color: context.brasa.danger,
                              ),
                            ),
                          ),
                        SplgButton(
                          title: loginViewButton,
                          loading: viewModel.isBusy,
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            viewModel.onLogin();
                          },
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'Tu distribuidora te da de alta como chofer.',
                            textAlign: TextAlign.center,
                            style: type.caption,
                          ),
                        ),
                        SizedBox(height: context.sp(40)),
                        Center(child: SplgLogo(height: context.sp(14))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  LoginViewModel viewModelBuilder(BuildContext context) => LoginViewModel();

  @override
  void onViewModelReady(LoginViewModel viewModel) {
    syncFormWithViewModel(viewModel);
  }

  @override
  void onDispose(LoginViewModel viewModel) {
    super.onDispose(viewModel);
    disposeForm();
  }
}
