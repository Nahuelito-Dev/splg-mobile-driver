import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked/stacked_annotations.dart';

import 'package:driver_mobile/ui/common/app_strings.dart';

import 'login_view.form.dart';
import 'login_viewmodel.dart';

@FormView(fields: [
  FormTextField(name: 'email'),
  FormTextField(name: 'password'),
])
class LoginView extends StackedView<LoginViewModel> with $LoginView {
  const LoginView({super.key});

  @override
  Widget builder(
    BuildContext context,
    LoginViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/logo.png',
                    height: 78,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    loginViewTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loginViewDescription,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 60),
                  _buildEmailAndPassword(context, viewModel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailAndPassword(
      BuildContext context, LoginViewModel viewModel) {
    final color = Theme.of(context).colorScheme.outline.withAlpha(70);
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: color,
        ));

    return Column(
      children: [
        TextFormField(
          controller: emailController,
          focusNode: emailFocusNode,
          enabled: !viewModel.isBusy,
          decoration: InputDecoration(
              fillColor: Theme.of(context).colorScheme.surface,
              prefixIcon: Icon(Icons.email_outlined, color: color),
              hintText: loginViewHintEmail,
              hintStyle: TextStyle(color: color),
              border: border,
              enabledBorder: border,
              disabledBorder: border),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: passwordController,
          focusNode: passwordFocusNode,
          enabled: !viewModel.isBusy,
          decoration: InputDecoration(
              fillColor: Theme.of(context).colorScheme.surface,
              prefixIcon: Icon(Icons.lock_outline, color: color),
              hintText: loginViewHintPassword,
              hintStyle: TextStyle(color: color),
              border: border,
              enabledBorder: border,
              disabledBorder: border),
          obscureText: true,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: viewModel.isBusy ? null : () {},
            child: Text(
              loginForgotPassword,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        if (viewModel.errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            viewModel.errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 32),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            minimumSize: const Size.fromHeight(44),
          ),
          onPressed: !viewModel.isBusy
              ? () {
                  FocusScope.of(context).unfocus();
                  viewModel.onLogin();
                }
              : null,
          child: viewModel.isBusy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(loginViewButton),
        ),
      ],
    );
  }

  @override
  LoginViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      LoginViewModel();

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
