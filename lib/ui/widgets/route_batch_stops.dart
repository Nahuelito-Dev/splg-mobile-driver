import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/models/maintenance.dart' show formatArTime;
import 'package:splg_driver/models/route_batch.dart';

/// "1,2 km" (con coma); sin decimales si es entero.
String kmText(double km) {
  final s = km == km.roundToDouble()
      ? km.toStringAsFixed(0)
      : km.toStringAsFixed(1).replaceAll('.', ',');
  return '$s km';
}

/// "75,5 kg".
String kgText(double kg) {
  final s = kg == kg.roundToDouble()
      ? kg.toStringAsFixed(0)
      : kg.toStringAsFixed(1).replaceAll('.', ',');
  return '$s kg';
}

/// Las paradas de un recorrido en orden de entrega, sobre el degradé de marca:
/// la oferta y, ya aceptado, el recorrido en curso. Se numeran 1..M por su
/// posición (la misma cuenta que «parada N de M»); [currentOrderId] marca la
/// parada que se está repartiendo y las entregadas quedan como hechas.
class RouteBatchStopList extends StatelessWidget {
  const RouteBatchStopList({
    super.key,
    required this.stops,
    this.currentOrderId,
    this.shrinkWrap = false,
  });

  final List<RouteBatchStop> stops;
  final String? currentOrderId;

  /// Dentro de una hoja que se ajusta al contenido.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => ListView.separated(
        shrinkWrap: shrinkWrap,
        itemCount: stops.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => RouteBatchStopTile(
          stop: stops[i],
          number: i + 1,
          current: stops[i].orderId == currentOrderId,
        ),
      );
}

/// Una parada: número, dirección, cliente, garrafas, llegada y franja.
class RouteBatchStopTile extends StatelessWidget {
  const RouteBatchStopTile({
    super.key,
    required this.stop,
    required this.number,
    this.current = false,
  });

  final RouteBatchStop stop;

  /// Posición entre las paradas que siguen en el lote (1 = primera).
  final int number;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final eta = stop.etaAt;
    final done = stop.isDelivered && !current;
    final strong = done ? Colors.white60 : Colors.white;
    final soft = done ? Colors.white54 : Colors.white70;
    final caption = [
      if (eta != null) 'Llegada ${formatArTime(eta)}',
      if (number > 1 && stop.legDistanceKm > 0)
        '${kmText(stop.legDistanceKm)} desde la anterior',
      if (stop.slotText != null) stop.slotText!,
    ].join(' - ');
    return Container(
      key: Key('batch-stop-$number'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: current ? 0.26 : 0.14),
        borderRadius: BorderRadius.circular(16),
        border: current ? Border.all(color: Colors.white, width: 1.5) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: done ? Colors.white54 : Colors.white,
            child: done
                ? Icon(SplgIcons.ok,
                    key: Key('batch-stop-done-$number'),
                    size: 18,
                    color: Colors.black87)
                : Text('$number',
                    style: type.bodyStrong.copyWith(color: Colors.black87)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (current)
                  Text('Estás acá',
                      key: const Key('batch-stop-current'),
                      style: type.caption.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                if (done)
                  Text('Parada $number · Entregada',
                      style: type.caption.copyWith(
                          color: strong, fontWeight: FontWeight.w700)),
                Text(stop.address ?? 'Dirección no disponible',
                    style: type.bodyStrong.copyWith(color: strong)),
                if (stop.customerName != null)
                  Text(stop.customerName!,
                      style: type.caption.copyWith(color: soft)),
                if (stop.items.isNotEmpty)
                  Text(stop.itemsText,
                      style: type.caption.copyWith(color: soft)),
                if (caption.isNotEmpty && !done)
                  Text(caption, style: type.caption.copyWith(color: soft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
