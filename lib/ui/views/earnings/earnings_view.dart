import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'earnings_viewmodel.dart';

class EarningsView extends StackedView<EarningsViewModel> {
  const EarningsView({super.key});

  @override
  EarningsViewModel viewModelBuilder(BuildContext context) =>
      EarningsViewModel();

  @override
  void onViewModelReady(EarningsViewModel viewModel) => viewModel.load();

  @override
  Widget builder(BuildContext context, EarningsViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return LoadScaffold(
      title: 'Estadísticas',
      model: model,
      builder: (context) {
        final s = model.summary!;
        final today = model.now();
        const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
        final first = today.subtract(const Duration(days: 6));
        final (count, amount) = switch (model.period) {
          0 => (s.monthCount, s.month),
          1 => (s.weekCount, s.week),
          2 => (s.yesterdayCount, s.yesterday),
          _ => (s.todayCount, s.today),
        };
        Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: type.bodyStrong),
                  Text(value, style: type.bodyStrong),
                ],
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              SplgSoftCard(
                label: 'Total hoy',
                amount: formatMoney(s.today),
                amountKey: const Key('earnings-today'),
                caption: s.todayCount == 1
                    ? '1 entrega hoy'
                    : '${s.todayCount} entregas hoy',
              ),
              const SizedBox(height: 10),
              SplgBarChartCard(
                title: 'Ganancia semanal',
                subtitle: '${formatDate(first)} al ${formatDate(today)}',
                infoMessage:
                    'Es lo entregado en cada uno de los últimos 7 días.',
                values: s.lastSevenDays,
                labels: [
                  for (var i = 0; i < 7; i++)
                    days[today.subtract(Duration(days: 6 - i)).weekday - 1],
                ],
              ),
              Divider(color: brasa.outline, height: 30),
              Align(
                alignment: Alignment.centerLeft,
                child: SplgChoiceChips(
                  labels: const ['Mes', 'Semana', 'Ayer', 'Hoy'],
                  selected: model.period,
                  onSelected: model.selectPeriod,
                ),
              ),
              const SizedBox(height: 12),
              row('Entregas realizadas', '$count'),
              row('Monto entregado', formatMoney(amount)),
              Divider(color: brasa.outline, height: 30),
              row('Entregas en total', '${s.totalCount}'),
              row('Monto total entregado', formatMoney(s.total)),
              const SizedBox(height: 10),
              Text(
                'Son los montos cobrados de los pedidos entregados, de todo tu '
                'historial: si había seña paga, cuenta el saldo. No incluyen '
                'descuentos ni comisiones.',
                style: type.caption,
              ),
            ],
          ),
        );
      },
    );
  }
}
