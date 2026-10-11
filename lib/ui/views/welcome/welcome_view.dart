import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/ui/widgets/welcome_blob.dart';
import 'welcome_viewmodel.dart';

class WelcomeView extends StackedView<WelcomeViewModel> {
  const WelcomeView({super.key});

  @override
  WelcomeViewModel viewModelBuilder(BuildContext context) => WelcomeViewModel();

  @override
  Widget builder(BuildContext context, WelcomeViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final white = type.title.copyWith(color: Colors.white);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
          child: Column(
            children: [
              WelcomeBlob(
                child: SplgIllustration.welcome.image(),
              ),
              SizedBox(height: context.sp(14)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.sp(28)),
                child: Column(
                  children: [
                    Text('Bienvenido/a',
                        textAlign: TextAlign.center,
                        style: white.copyWith(fontSize: context.sp(20))),
                    SizedBox(height: context.sp(10)),
                    Text(
                      'a SPLG Chofer: recibí pedidos de tu distribuidora y '
                      'entregá garrafas desde tu celular.',
                      textAlign: TextAlign.center,
                      style: type.body.copyWith(
                          color: Colors.white, fontSize: context.sp(13)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.sp(28)),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    children: [
                      SplgButton(
                        title: 'Comenzar',
                        style: SplgButtonStyle.white,
                        onPressed: model.goToLogin,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
