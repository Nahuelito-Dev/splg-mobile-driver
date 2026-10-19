import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'pending_collections_viewmodel.dart';

/// "Cobros pendientes": entregas en efectivo sin cobro registrado.
class PendingCollectionsView extends StackedView<PendingCollectionsViewModel> {
  const PendingCollectionsView({super.key});

  @override
  PendingCollectionsViewModel viewModelBuilder(BuildContext context) =>
      PendingCollectionsViewModel();

  @override
  void onViewModelReady(PendingCollectionsViewModel viewModel) =>
      viewModel.load();

  @override
  Widget builder(
      BuildContext context, PendingCollectionsViewModel model, Widget? child) {
    return LoadScaffold(
      title: 'Cobros pendientes',
      centerTitle: false,
      model: model,
      builder: (context) {
        if (model.orders.isEmpty) {
          return const SplgEmptyState(
            illustration: SplgIllustration.success,
            title: 'Todo cobrado',
            message: 'No tenés entregas en efectivo con el cobro pendiente.',
          );
        }
        return RefreshIndicator(
          onRefresh: model.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              for (final o in model.orders)
                SplgListRow(
                  title: '${formatDate(o.date)}'
                      '${o.customerName != null ? ' - ${o.customerName}' : ''}',
                  trailing: formatMoney(o.amountToCollect),
                  onTap: () => model.open(o),
                ),
            ],
          ),
        );
      },
    );
  }
}
