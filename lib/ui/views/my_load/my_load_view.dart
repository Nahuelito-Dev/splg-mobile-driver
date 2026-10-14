import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/truck_load.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'my_load_viewmodel.dart';

/// Mi carga: lo que el chofer lleva en el camión, sólo lectura.
class MyLoadView extends StackedView<MyLoadViewModel> {
  const MyLoadView({super.key});

  @override
  MyLoadViewModel viewModelBuilder(BuildContext context) => MyLoadViewModel();

  @override
  void onViewModelReady(MyLoadViewModel viewModel) => viewModel.load();

  @override
  Widget builder(BuildContext context, MyLoadViewModel model, Widget? child) {
    return LoadScaffold(
      title: 'Mi carga',
      centerTitle: false,
      model: model,
      builder: (context) {
        final load = model.openLoad;
        return RefreshIndicator(
          onRefresh: model.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (model.refreshError != null && load == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _RefreshError(message: model.refreshError!),
                  ),
                ),
              if (load == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SplgEmptyState(
                    title: 'Sin carga abierta',
                    message: model.requiresOpenLoad
                        ? 'Tu distribuidora te pide una carga abierta para '
                            'recibir pedidos. Pedile que te abra la carga.'
                        : 'No tenés una carga de camión abierta. La abre tu '
                            'distribuidora desde el panel.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (model.refreshError != null) ...[
                        _RefreshError(message: model.refreshError!),
                        const SizedBox(height: 12),
                      ],
                      _LoadHeader(load: load),
                      for (final item in load.items) _ItemCard(item: item),
                      Text(
                        'La carga la abre y la rinde tu distribuidora. Acá ves '
                        'lo que llevás y lo que te queda; se actualiza con '
                        'cada entrega.',
                        style: SplgType.of(context).caption,
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RefreshError extends StatelessWidget {
  const _RefreshError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brasa = context.brasa;
    return Container(
      key: const Key('my-load-refresh-error'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brasa.warnSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(SplgIcons.error, color: brasa.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text('No pudimos actualizar. $message',
                style: SplgType.of(context).caption),
          ),
        ],
      ),
    );
  }
}

SplgTone _tone(TruckLoadStatus s) => switch (s) {
      TruckLoadStatus.onRoute => SplgTone.success,
      TruckLoadStatus.loading => SplgTone.info,
      TruckLoadStatus.returned => SplgTone.warn,
      TruckLoadStatus.cancelled => SplgTone.danger,
      _ => SplgTone.neutral,
    };

class _LoadHeader extends StatelessWidget {
  const _LoadHeader({required this.load});

  final TruckLoad load;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final opened = load.openedAt;
    final departed = load.departedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text('Carga N° ${load.number}', style: type.subtitle)),
            SplgStatusBadge(
              key: const Key('my-load-status'),
              label: load.status.label,
              tone: _tone(load.status),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SplgSoftCard(
          label: 'Camión',
          amount: load.carPatent ?? 'Sin patente',
          amountKey: const Key('my-load-patent'),
        ),
        const SizedBox(height: 20),
        SplgInfoSection(
          icon: SplgIcons.truck,
          title: 'Datos de la carga',
          rows: [
            SplgInfoRow(title: 'Depósito de origen:', value: load.originName),
            if (opened != null)
              SplgInfoRow(title: 'Apertura:', value: formatDateTime(opened)),
            if (departed != null)
              SplgInfoRow(title: 'Salida:', value: formatDateTime(departed)),
            if (load.helperName != null)
              SplgInfoRow(title: 'Ayudante:', value: load.helperName),
          ],
        ),
        Text('Garrafas', style: type.subtitle),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final TruckLoadItem item;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    Widget row(String label, int value, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: type.body),
              Text('$value', key: key, style: type.bodyStrong),
            ],
          ),
        );
    return Container(
      key: Key('my-load-item-${item.type}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: brasa.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.type, style: type.subtitle),
          Divider(color: brasa.outlineSoft, height: 20),
          row('Llenas cargadas', item.loadedFull),
          if (item.reloadedFull > 0)
            row('Llenas repuestas en ruta', item.reloadedFull),
          row('Entregadas', item.deliveredFull),
          row('Vacías con las que salió', item.loadedEmpty),
          row('Vacías recolectadas', item.collectedEmpty),
          Divider(color: brasa.outlineSoft, height: 20),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: brasa.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                row('Te quedan llenas', item.expectedFull,
                    key: Key('my-load-left-full-${item.type}')),
                row('Vacías en el camión', item.expectedEmpty),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
