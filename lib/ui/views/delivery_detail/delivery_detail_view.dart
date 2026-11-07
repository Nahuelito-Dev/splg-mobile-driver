import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/driver_header.dart';
import 'package:splg_driver/models/order_history.dart';
import 'package:splg_driver/ui/widgets/order_status_chip.dart';
import 'delivery_detail_viewmodel.dart';

/// Detalle de una entrega del historial (sólo lectura): el pedido viene
/// completo de la lista; las incidencias y el historial de estados se leen del
/// back.
class DeliveryDetailView extends StackedView<DeliveryDetailViewModel> {
  const DeliveryDetailView({super.key, required this.order});

  final DriverOrder order;

  static String paymentLabel(String? raw) => switch (raw) {
        'cash' => 'Efectivo',
        'transfer' => 'Transferencia',
        'card' || 'credit_card' || 'debit_card' => 'Tarjeta',
        'mercado_pago' || 'mercadopago' => 'Mercado Pago',
        null => 'Sin datos',
        final other => other,
      };

  @override
  DeliveryDetailViewModel viewModelBuilder(BuildContext context) =>
      DeliveryDetailViewModel(order);

  @override
  void onViewModelReady(DeliveryDetailViewModel viewModel) => viewModel.load();

  @override
  Widget builder(
      BuildContext context, DeliveryDetailViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    final divider = Divider(color: brasa.outline, height: 30);

    Widget box(IconData icon, String text) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: brasa.primarySoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: brasa.primaryStrong),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: type.bodyStrong)),
            ],
          ),
        );

    return Scaffold(
      appBar: const DriverHeader(title: 'Mi entrega'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            SplgSectionBar(
                title:
                    '${formatLongDate(order.date)} - ${formatTime(order.date)} hs'),
            divider,
            SplgSoftCard(
              label: 'Método de pago: ${paymentLabel(order.paymentMethod)}',
              amount: formatMoney(order.amountToCollect),
              amountKey: const Key('detail-total'),
            ),
            const SizedBox(height: 10),
            Align(
                alignment: Alignment.centerLeft,
                child: OrderStatusChip(status: order.status)),
            divider,
            if (order.customerName != null)
              Row(
                children: [
                  const SplgAvatar(radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(order.customerName!,
                        style: type.subtitle
                            .copyWith(fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            if (order.customerName != null) divider,
            if (order.address != null) box(SplgIcons.location, order.address!),
            for (final l in order.lines)
              box(SplgIcons.deliveries, '${l.quantity} x ${l.label}'),
            if (order.cancellationReason != null)
              box(SplgIcons.error,
                  'Motivo de cancelación: ${order.cancellationReason!}'),
            divider,
            _IncidentsSection(model: model),
            divider,
            _HistorySection(model: model),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Título de una sección con su estado: cargando, error con reintento, vacía o
/// con sus filas.
class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.section,
    required this.emptyText,
    required this.onRetry,
    required this.keyPrefix,
    required this.itemBuilder,
  });

  final String title;
  final DetailSection<T> section;
  final String emptyText;
  final VoidCallback onRetry;
  final String keyPrefix;
  final Widget Function(int index, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: type.subtitle),
        const SizedBox(height: 10),
        if (section.loading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                key: Key('$keyPrefix-loading'),
                width: 22,
                height: 22,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (section.error != null) ...[
          Text(section.error!,
              key: Key('$keyPrefix-error'),
              style: type.body.copyWith(color: brasa.danger)),
          const SizedBox(height: 6),
          SplgButton(
            key: Key('$keyPrefix-retry'),
            title: 'Reintentar',
            style: SplgButtonStyle.outlined,
            expand: false,
            onPressed: onRetry,
          ),
        ] else if (section.isEmpty)
          Text(emptyText, key: Key('$keyPrefix-empty'), style: type.caption)
        else
          for (final (i, item) in section.items.indexed) itemBuilder(i, item),
      ],
    );
  }
}

SplgTone _incidentTone(IncidentStatus s) => switch (s) {
      IncidentStatus.resolved => SplgTone.success,
      IncidentStatus.discarded => SplgTone.neutral,
      IncidentStatus.open => SplgTone.warn,
    };

class _IncidentsSection extends StatelessWidget {
  const _IncidentsSection({required this.model});

  final DeliveryDetailViewModel model;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return _Section<OrderIncident>(
      title: 'Incidencias',
      section: model.incidents,
      emptyText: 'Este pedido no tiene incidencias.',
      onRetry: model.loadIncidents,
      keyPrefix: 'detail-incidents',
      itemBuilder: (_, i) => Container(
        key: Key('detail-incident-${i.id}'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: brasa.outline),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(i.typeLabel, style: type.bodyStrong)),
                SplgStatusBadge(
                    label: i.status.label, tone: _incidentTone(i.status)),
              ],
            ),
            if (i.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(i.description, style: type.body),
            ],
            if (i.createdAt != null) ...[
              const SizedBox(height: 4),
              Text('Reportada el ${formatDateTime(i.createdAt!)}',
                  style: type.caption),
            ],
            if (i.resolutionNote != null) ...[
              const SizedBox(height: 8),
              Container(
                key: Key('detail-incident-note-${i.id}'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: brasa.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                    '${i.status == IncidentStatus.discarded ? 'Descartada' : 'Resolución'}: '
                    '${i.resolutionNote}',
                    style: type.body),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.model});

  final DeliveryDetailViewModel model;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return _Section<StatusChange>(
      title: 'Historial de estados',
      section: model.history,
      emptyText: 'Este pedido no tiene historial de estados.',
      onRetry: model.loadHistory,
      keyPrefix: 'detail-history',
      itemBuilder: (index, c) => Padding(
        key: Key('detail-history-$index'),
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(c.isNote ? SplgIcons.notes : SplgIcons.clock,
                size: 18, color: brasa.primaryStrong),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, style: type.bodyStrong),
                  Text(
                      [
                        if (c.changedAt != null) formatDateTime(c.changedAt!),
                        c.actorLabel,
                      ].join(' - '),
                      style: type.caption),
                  if (c.reason != null) Text(c.reason!, style: type.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
