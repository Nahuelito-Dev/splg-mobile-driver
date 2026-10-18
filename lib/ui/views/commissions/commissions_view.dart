import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/labeled_field.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'commissions_viewmodel.dart';

/// "Mis comisiones": lo ganado en el período, lo pendiente y lo liquidado.
class CommissionsView extends StackedView<CommissionsViewModel> {
  const CommissionsView({super.key});

  @override
  CommissionsViewModel viewModelBuilder(BuildContext context) =>
      CommissionsViewModel();

  @override
  void onViewModelReady(CommissionsViewModel viewModel) => viewModel.load();

  @override
  Widget builder(
      BuildContext context, CommissionsViewModel model, Widget? child) {
    final type = SplgType.of(context);
    return LoadScaffold(
      title: 'Mis comisiones',
      centerTitle: false,
      model: model,
      builder: (context) {
        final d = model.data;
        final (from, to) = model.range;
        return RefreshIndicator(
          onRefresh: model.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: [
              SplgChoiceChips(
                labels: const ['Este mes', 'Mes anterior', '7 días'],
                selected: model.period,
                onSelected: model.selectPeriod,
              ),
              const SizedBox(height: 14),
              SplgSoftCard(
                label: 'Total del período',
                amount: formatMoney(d.totalAmount),
                amountKey: const Key('commissions-total'),
                caption: '${formatDate(from)} al ${formatDate(to)}',
              ),
              const SizedBox(height: 10),
              InfoRow('Pendiente de liquidar', formatMoney(d.pendingAmount)),
              InfoRow('Ya liquidado', formatMoney(d.liquidatedAmount)),
              const Divider(height: 28),
              if (d.entries.isEmpty)
                Text('No tenés movimientos en este período.',
                    key: const Key('commissions-empty'), style: type.body)
              else
                for (final e in d.entries)
                  InfoRow(
                    '${e.occurredAt == null ? '' : '${formatDate(e.occurredAt!)} · '}'
                    '${e.description}${e.liquidated ? ' (liquidada)' : ''}',
                    formatMoney(e.amount),
                  ),
              if (d.total > d.entries.length)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Se muestran ${d.entries.length} de ${d.total} '
                    'movimientos; el total incluye todos.',
                    style: type.caption,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
