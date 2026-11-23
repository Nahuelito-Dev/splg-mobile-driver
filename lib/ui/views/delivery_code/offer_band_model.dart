import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/services/delivery_offer_slot.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog_model.dart';

/// La oferta de pedido en la banda de la pantalla del QR. Misma cuenta
/// regresiva y misma aceptación en el back que el diálogo a pantalla completa;
/// contesta por [DeliveryOfferSlot] con la misma respuesta que daría el
/// diálogo. No pregunta por el mapa: con una entrega en curso el pedido queda
/// en espera y no se navega a ningún lado.
class OfferBandModel extends OrderOfferDialogModel {
  OfferBandModel({
    required this.offer,
    required DeliveryOfferSlot slot,
    super.trips,
  }) : _slot = slot;

  final Map<String, dynamic> offer;
  final DeliveryOfferSlot _slot;

  String? get orderId => offer['orderId']?.toString();

  /// Monto del pedido leído del back; mientras tanto, el del aviso.
  num? get total =>
      order?.total ??
      (offer['totalAmount'] is num ? offer['totalAmount'] as num : null);

  String? get paymentMethod =>
      order?.paymentMethod ?? offer['paymentMethod']?.toString();

  /// La oferta ya la está contestando otra interfaz (aceptación en vuelo).
  bool get takenElsewhere =>
      _slot.state == OfferSlotState.responding && !isAccepting;

  /// Arranca la cuenta hasta `expiresAt` y lee el detalle del pedido. Al
  /// vencer se contesta como un rechazo, igual que el diálogo.
  void begin() {
    _slot.addListener(_onSlot);
    start(offer['expiresAt'], () => _answer(DialogResponse(confirmed: false)));
    final id = orderId;
    if (id != null) load(id);
  }

  void _onSlot() => notifyListeners();

  /// Rechazo o vencimiento: sólo si la oferta sigue para decidir.
  void _answer(DialogResponse<dynamic> response) {
    if (!_slot.beginResponse(offer)) return;
    _slot.respond(offer, response);
  }

  void reject() {
    if (isAccepting || takenElsewhere) return;
    stop();
    _answer(DialogResponse(confirmed: false));
  }

  /// Acepta en el back y contesta con el resultado. La oferta queda tomada
  /// desde el toque: si mientras tanto se cierra la pantalla, nadie más la
  /// contesta ni se abre el diálogo a pantalla completa.
  Future<void> accept() async {
    final id = orderId;
    if (isAccepting) return;
    if (id == null) {
      missingOrder();
      return;
    }
    if (!_slot.beginResponse(offer)) return;
    final outcome = await acceptInBackend(id);
    _slot.respond(
        offer,
        DialogResponse(confirmed: true, data: {
          'map': 'stay',
          'lat': order?.lat,
          'lng': order?.lng,
          'accepted': outcome == AcceptOutcome.accepted,
          'refused': outcome == AcceptOutcome.refused,
          'error': acceptError,
        }));
  }

  @override
  void dispose() {
    _slot.removeListener(_onSlot);
    super.dispose();
  }
}
