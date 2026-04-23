import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'directions_viewmodel.dart';

class DirectionsView extends StackedView<DirectionsViewModel> {
  const DirectionsView({Key? key}) : super(key: key);

  @override
  Widget builder(
    BuildContext context,
    DirectionsViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Container(
        padding: const EdgeInsets.only(left: 25.0, right: 25.0),
        child: const Center(child: Text("DirectionsView")),
      ),
    );
  }

  @override
  DirectionsViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      DirectionsViewModel();
}
