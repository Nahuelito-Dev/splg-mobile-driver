import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/delivery_offer_slot.dart';

/// Pantallas del final de la entrega (QR y cobro) que muestran la oferta de
/// pedido como banda, sin taparse: la toman al abrir ([hostOffers]) y la
/// sueltan al cerrar ([releaseOffers]).
mixin OfferSlotHost on BaseViewModel {
  /// Para tests: el slot a usar en vez del del locator.
  DeliveryOfferSlot? get offerSlotOverride;

  DeliveryOfferSlot get offerSlot =>
      offerSlotOverride ?? locator<DeliveryOfferSlot>();

  bool _hostingOffers = false;

  /// Oferta de pedido esperando respuesta en la banda.
  Map<String, dynamic>? get pendingOffer => offerSlot.offer;

  /// Aviso no bloqueante para esta pantalla (próximo pedido).
  String? get offerNotice => offerSlot.notice;

  void _onOfferSlot() => rebuildUi();

  void hostOffers() {
    if (_hostingOffers) return;
    _hostingOffers = true;
    offerSlot.host();
    offerSlot.addListener(_onOfferSlot);
  }

  void releaseOffers() {
    if (!_hostingOffers) return;
    _hostingOffers = false;
    offerSlot.removeListener(_onOfferSlot);
    offerSlot.release();
  }
}
