import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/models/driver_data.dart';

/// Etiqueta de estado del pedido con los colores de estado de Brasa.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final DriverOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final b = context.brasa;
    final (fg, bg) = switch (status) {
      DriverOrderStatus.delivered => (b.success, b.successSoft),
      DriverOrderStatus.cancelled => (b.danger, b.dangerSoft),
      DriverOrderStatus.onTheWay || DriverOrderStatus.accepted => (
          b.info,
          b.infoSoft
        ),
      _ => (b.warn, b.warnSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}
