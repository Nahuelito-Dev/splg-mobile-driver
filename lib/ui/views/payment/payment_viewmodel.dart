import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/delivery_offer_slot.dart';
import 'package:splg_driver/services/payment_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/common/navigation_helpers.dart';
import 'package:splg_driver/ui/views/delivery_qr/offer_slot_host.dart';

/// Cobro del pedido ya entregado: medio de pago, total a cobrar y detalle.
///
/// En efectivo el pago queda pendiente hasta que el chofer lo confirma:
/// "Pago recibido" llama al back y recién ahí sigue al cierre (si falla,
/// muestra el motivo y deja reintentar); "El cliente no pagó" pide una nota
/// opcional, avisa al back y sigue al cierre con un aviso. Con Mercado Pago lo
/// paga el cliente: se muestra el estado, sin esos botones.
/// Una oferta de pedido que llega (o quedó pendiente del QR) se muestra como
/// banda abajo, sin tapar el cobro.
class PaymentViewModel extends BaseViewModel with OfferSlotHost {
  PaymentViewModel(
      {required this.orderId,
      TripService? trips,
      PaymentRepository? payments,
      void Function()? goHome,
      DeliveryOfferSlot? offers})
      : _tripsOverride = trips,
        _paymentsOverride = payments,
        _goHome = goHome ?? popToHome,
        _offersOverride = offers;

  final DeliveryOfferSlot? _offersOverride;
  @override
  DeliveryOfferSlot? get offerSlotOverride => _offersOverride;

  @override
  void dispose() {
    releaseOffers();
    super.dispose();
  }

  final void Function() _goHome;

  final String orderId;
  final TripService? _tripsOverride;
  final PaymentRepository? _paymentsOverride;
  TripService get _trips => _tripsOverride ?? locator<TripService>();
  PaymentRepository get _payments =>
      _paymentsOverride ?? locator<PaymentRepository>();
  final _nav = locator<NavigationService>();

  TripOrder? order;
  String? loadError;

  /// Hay una confirmación o un reporte en curso (los botones se traban).
  bool submitting = false;

  /// Motivo del último fallo al confirmar o reportar (se puede reintentar).
  String? actionError;

  Future<void> load() async {
    loadError = null;
    setBusy(true);
    try {
      order = await _trips.order(orderId);
    } catch (e) {
      loadError = _text(e, 'No pudimos cargar el cobro.');
    }
    setBusy(false);
  }

  bool get isCash => order?.isCash ?? true;

  /// El pago ya está registrado como pagado (no hay nada que confirmar).
  bool get isPaid => order?.isPaid ?? false;

  /// Ya se informó que el cliente no pagó (lo resuelve la distribuidora).
  bool get isUnpaid => order?.isUnpaid ?? false;

  /// Hay que cobrar en efectivo y todavía no está registrado ni informado como
  /// impago (el back rechaza "Pago recibido" sobre un impago).
  bool get needsCashConfirmation => isCash && order?.paymentStatus == 'pending';

  /// Estado del pago online para mostrar.
  String get onlineStatus => switch (order?.paymentStatus) {
        'paid' => 'Pagado por el cliente',
        'failed' => 'El pago falló',
        _ => 'Pendiente de pago del cliente',
      };

  String get confirmLabel =>
      needsCashConfirmation ? 'Pago recibido' : 'Continuar';

  String _text(Object e, String fallback) => e is DioException
      ? ApiErrorText.of(e.response?.statusCode, e.response?.data)
      : fallback;

  /// El reporte de impago es idempotente por clave: reintentarlo con la nota
  /// cambiada da 422. En ese caso lo que se registró antes manda, así que se
  /// relee el pedido para mostrar su estado real.
  Future<void> _refreshAfterConflict(Object e) async {
    if (!isIdempotencyConflict(e) &&
        !(e is DioException && e.response?.statusCode == 409)) {
      return;
    }
    try {
      order = await _trips.order(orderId);
    } catch (_) {
      // Se conserva el pedido que ya estaba en pantalla.
    }
  }

  /// Texto al pie según el estado del cobro.
  String get footerText {
    if (needsCashConfirmation) {
      return 'Cuando recibas el dinero, tocá el botón para registrar el pago.';
    }
    if (isCash && !isPaid && !isUnpaid) {
      return 'El cobro ya no está pendiente: lo resuelve tu distribuidora. '
          'Seguí cuando quieras.';
    }
    if (isUnpaid) {
      return 'Ya informaste que el cliente no pagó: lo resuelve tu '
          'distribuidora. Seguí cuando quieras.';
    }
    return 'El pedido ya figura como pagado; seguí cuando quieras.';
  }

  /// "Más tarde": sale sin registrar nada y deja el Inicio libre. El cobro
  /// queda en "Cobros pendientes". También sirve cuando el pedido no carga.
  void later() {
    _trips.endFlow();
    _goHome();
  }

  /// "Pago recibido" (efectivo pendiente) o "Continuar" (ya pagado / online).
  Future<void> confirm() async {
    if (submitting) return;
    if (!needsCashConfirmation) {
      if (isUnpaid) {
        await _nav.replaceWithCompletedView(orderId: orderId, unpaid: true);
      } else {
        await _nav.replaceWithCompletedView(orderId: orderId);
      }
      return;
    }
    submitting = true;
    actionError = null;
    notifyListeners();
    bool paid;
    try {
      paid = await _payments.confirmReceived(orderId);
    } catch (e) {
      actionError = _text(e, 'No pudimos registrar el pago. Probá de nuevo.');
      await _refreshAfterConflict(e);
      submitting = false;
      notifyListeners();
      return;
    }
    submitting = false;
    notifyListeners();
    await _nav.replaceWithCompletedView(orderId: orderId, paid: paid);
  }

  /// "El cliente no pagó": avisa al back (con la nota, si hay) y sigue al cierre
  /// con un aviso. Sólo en efectivo pendiente.
  Future<void> reportUnpaid({String? note, Uint8List? photo}) async {
    if (submitting || !needsCashConfirmation) return;
    submitting = true;
    actionError = null;
    notifyListeners();
    String? incidentId;
    try {
      incidentId = await _payments.reportUnpaid(orderId, note: note);
    } catch (e) {
      actionError = actionErrorText(e,
          fallback: 'No pudimos registrar el reporte. Probá de nuevo.');
      await _refreshAfterConflict(e);
      submitting = false;
      notifyListeners();
      return;
    }
    // La foto es opcional: si no sube, el reporte ya quedó registrado.
    var photoFailed = false;
    if (photo != null && incidentId != null) {
      try {
        await _payments.uploadIncidentPhoto(incidentId, photo);
      } catch (e) {
        photoFailed = true;
      }
    }
    submitting = false;
    notifyListeners();
    await _nav.replaceWithCompletedView(
        orderId: orderId, unpaid: true, photoFailed: photoFailed);
  }
}
