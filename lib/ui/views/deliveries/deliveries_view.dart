import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'package:splg_driver/ui/widgets/order_status_chip.dart';
import 'deliveries_viewmodel.dart';

class DeliveriesView extends StackedView<DeliveriesViewModel> {
  const DeliveriesView({super.key});

  @override
  DeliveriesViewModel viewModelBuilder(BuildContext context) =>
      DeliveriesViewModel();

  @override
  void onViewModelReady(DeliveriesViewModel viewModel) => viewModel.load();

  @override
  Widget builder(
      BuildContext context, DeliveriesViewModel model, Widget? child) {
    return LoadScaffold(
      title: 'Mis entregas',
      model: model,
      builder: (context) {
        if (model.orders.isEmpty) {
          return const SplgEmptyState(
            message: 'No tenés ninguna entrega realizada.',
          );
        }
        return _DeliveriesList(model: model);
      },
    );
  }
}

/// Lista agrupada por día; al llegar al final pide la página siguiente.
class _DeliveriesList extends StatefulWidget {
  const _DeliveriesList({required this.model});

  final DeliveriesViewModel model;

  @override
  State<_DeliveriesList> createState() => _DeliveriesListState();
}

class _DeliveriesListState extends State<_DeliveriesList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final model = widget.model;
    if (model.moreError != null) return;
    if (_scroll.position.extentAfter < 300) model.loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final type = SplgType.of(context);
    final groups = <DateTime, List<DriverOrder>>{};
    for (final o in model.orders) {
      final d = DateTime(o.date.year, o.date.month, o.date.day);
      groups.putIfAbsent(d, () => []).add(o);
    }
    final days = groups.keys.toList();

    // Si la primera página no llena la pantalla no hay scroll que dispare la
    // carga: se pide la siguiente apenas se dibuja.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent == 0 && model.moreError == null) {
        model.loadMore();
      }
    });

    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          for (final day in days) ...[
            SplgSectionBar(
              title: formatLongDate(day),
              trailing: model.dayTotalLabel(day),
            ),
            for (final o in groups[day]!)
              SplgListRow(
                title: '${formatTime(o.date)} hs'
                    '${o.customerName != null ? ' - ${o.customerName}' : ''}',
                trailing: formatMoney(o.amountToCollect),
                badge: o.status == DriverOrderStatus.delivered
                    ? null
                    : OrderStatusChip(status: o.status),
                onTap: () => model.open(o),
              ),
            const SizedBox(height: 6),
          ],
          if (model.loadingMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (model.moreError != null)
            Column(
              children: [
                Text(model.moreError!, style: type.caption),
                SplgButton(
                  title: 'Reintentar',
                  style: SplgButtonStyle.outlined,
                  expand: false,
                  onPressed: () => model.loadMore(retry: true),
                ),
              ],
            )
          else if (model.hasMore)
            Center(
              child: TextButton(
                onPressed: model.loadMore,
                child: const Text('Cargar más'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Text(
                    model.total == 1
                        ? '1 entrega'
                        : '${model.total} entregas en total',
                    style: type.caption),
              ),
            ),
        ],
      ),
    );
  }
}
