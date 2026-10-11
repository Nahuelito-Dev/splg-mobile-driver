import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'startup_viewmodel.dart';

class StartupView extends StackedView<StartupViewModel> {
  const StartupView({super.key});

  @override
  Widget builder(
    BuildContext context,
    StartupViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      body: SplgGradientBackground(
        gradient: SplgGradients.splash,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SplgLogo(height: context.sp(40), color: Colors.white),
              const SizedBox(height: 28),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  StartupViewModel viewModelBuilder(BuildContext context) => StartupViewModel();

  @override
  void onViewModelReady(StartupViewModel viewModel) => SchedulerBinding.instance
      .addPostFrameCallback((timeStamp) => viewModel.runStartupLogic());
}
