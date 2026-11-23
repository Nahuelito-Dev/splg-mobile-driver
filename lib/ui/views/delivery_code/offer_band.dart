import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/delivery_offer_slot.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog.dart'
    show paymentLabel;

import 'offer_band_model.dart';

/// Oferta de pedido compacta, abajo de la pantalla del QR: el QR y el código
/// quedan quietos y a la vista mientras el cliente escanea, y el chofer tiene
/// a mano la cuenta regresiva y las dos decisiones.
class OfferBand extends StatelessWidget {
  const OfferBand({super.key, required this.offer, required this.slot});

  final Map<String, dynamic> offer;
  final DeliveryOfferSlot slot;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<OfferBandModel>.reactive(
      viewModelBuilder: () => OfferBandModel(offer: offer, slot: slot),
      onViewModelReady: (m) => m.begin(),
      builder: (context, model, _) => _Band(model: model),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.model});
  final OfferBandModel model;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    final total = model.total;
    final order = model.order;
    final where = order?.address ??
        (model.loading ? 'Cargando el pedido…' : 'Dirección no disponible');
    return Container(
      key: const Key('offer-band'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(SplgIcons.flame, size: 18, color: brasa.primaryStrong),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Pedido nuevo para después',
                      style:
                          type.subtitle.copyWith(color: brasa.primaryStrong)),
                ),
                Text(total == null ? '' : formatMoney(total),
                    key: const Key('offer-band-total'), style: type.heading),
              ],
            ),
            const SizedBox(height: 4),
            Text('$where · ${paymentLabel(model.paymentMethod)}',
                key: const Key('offer-band-address'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.body.copyWith(color: brasa.ink2)),
            if (model.acceptError != null && model.orderId == null) ...[
              const SizedBox(height: 4),
              Text(model.acceptError!,
                  style: type.body.copyWith(color: brasa.danger)),
            ],
            const SizedBox(height: 10),
            SplgCountdownBar(
              remaining: model.remainingSeconds,
              total: model.totalSeconds,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SplgButton(
                    key: const Key('offer-band-reject'),
                    title: 'Rechazar',
                    style: SplgButtonStyle.outlined,
                    onPressed: model.isFinished || model.takenElsewhere
                        ? null
                        : model.reject,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SplgButton(
                    key: const Key('offer-band-accept'),
                    title: 'Aceptar',
                    loading: model.isAccepting || model.takenElsewhere,
                    onPressed: model.isFinished ||
                            model.isAccepting ||
                            model.takenElsewhere
                        ? null
                        : model.accept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso que no bloquea, abajo de la pantalla del QR (próximo pedido
/// aceptado): se lee de un vistazo y no tapa el QR ni pide tocar nada.
class OfferNotice extends StatelessWidget {
  const OfferNotice({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return Container(
      key: const Key('offer-notice'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(SplgIcons.ok, size: 20, color: brasa.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: type.bodyStrong.copyWith(color: brasa.ink2)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo de abajo de las pantallas del final de la entrega: la banda de la
/// oferta, el aviso del próximo pedido o nada.
class OfferSlotArea extends StatelessWidget {
  const OfferSlotArea({
    super.key,
    required this.offer,
    required this.notice,
    required this.slot,
  });

  final Map<String, dynamic>? offer;
  final String? notice;
  final DeliveryOfferSlot slot;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    if (o != null) {
      return OfferBand(key: ValueKey(o['orderId']), offer: o, slot: slot);
    }
    final n = notice;
    if (n != null) return OfferNotice(text: n);
    return const SizedBox.shrink();
  }
}
