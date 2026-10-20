import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/ui/widgets/driver_header.dart';
import 'change_password_viewmodel.dart';

SplgFieldStatus _status(FieldState s) => switch (s) {
      FieldState.neutral => SplgFieldStatus.neutral,
      FieldState.valid => SplgFieldStatus.valid,
      FieldState.invalid => SplgFieldStatus.invalid,
    };

class ChangePasswordView extends StackedView<ChangePasswordViewModel> {
  const ChangePasswordView({super.key});

  @override
  ChangePasswordViewModel viewModelBuilder(BuildContext context) =>
      ChangePasswordViewModel();

  @override
  Widget builder(
      BuildContext context, ChangePasswordViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return Scaffold(
      appBar: const DriverHeader(
          title: 'Cambiar contraseña', centerTitle: false, bell: false),
      body: SafeArea(
        child: model.done
            ? _Done(onClose: () => Navigator.of(context).pop())
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Field(
                            label: 'Ingresá tu contraseña actual',
                            fieldKey: const Key('current'),
                            onChanged: model.onCurrentChanged,
                            status: model.currentState,
                            error: model.currentError,
                            enabled: !model.isBusy,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: model.forgotPassword,
                              child: Text('Olvidé mi contraseña',
                                  style: type.action.copyWith(
                                      fontSize: context.sp(10),
                                      decoration: TextDecoration.underline)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _Field(
                            label: 'Ingresá tu nueva contraseña',
                            fieldKey: const Key('next'),
                            onChanged: model.onNextChanged,
                            status: model.nextState,
                            error: model.nextError,
                            enabled: !model.isBusy,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              'Recordá que la contraseña debe tener al menos 8 '
                              'caracteres, una mayúscula y un número.',
                              textAlign: TextAlign.center,
                              style: type.captionStrong.copyWith(
                                  fontStyle: FontStyle.italic,
                                  fontSize: context.sp(10)),
                            ),
                          ),
                          _Field(
                            label: 'Repetí tu nueva contraseña',
                            fieldKey: const Key('repeat'),
                            onChanged: model.onRepeatChanged,
                            status: model.repeatState,
                            error: model.repeatError,
                            enabled: !model.isBusy,
                          ),
                          if (model.generalError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(model.generalError!,
                                  key: const Key('general-error'),
                                  style:
                                      type.body.copyWith(color: brasa.danger)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SplgButton(
                      title: 'Confirmar',
                      loading: model.isBusy,
                      onPressed: model.canSubmit ? model.submit : null,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.fieldKey,
    required this.onChanged,
    required this.status,
    required this.enabled,
    this.error,
  });

  final String label;
  final Key fieldKey;
  final ValueChanged<String> onChanged;
  final FieldState status;
  final String? error;
  final bool enabled;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: widget.fieldKey,
        child: SplgPasswordField(
          label: widget.label,
          controller: _controller,
          onChanged: widget.onChanged,
          status: _status(widget.status),
          errorText: widget.error,
          enabled: widget.enabled,
        ),
      );
}

class _Done extends StatelessWidget {
  const _Done({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Expanded(
            child: SplgEmptyState(
              illustration: SplgIllustration.success,
              title: '¡Contraseña actualizada!',
              message: 'Ya podés usar tu nueva contraseña la próxima vez.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SplgButton(title: 'Volver al perfil', onPressed: onClose),
          ),
        ],
      );
}
