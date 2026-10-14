import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/driver_header.dart';
import 'package:splg_driver/ui/widgets/order_status_chip.dart';

/// Detalle de una entrega del historial (sólo lectura, sin pedir nada al back:
/// el pedido ya vino completo en la lista).
class DeliveryDetailView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    final divider = Divider(color: brasa.primaryStrong, height: 30);

    Widget box(IconData icon, String text) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: brasa.primaryStrong.withValues(alpha: 0.1),
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
          ],
        ),
      ),
    );
  }
}
