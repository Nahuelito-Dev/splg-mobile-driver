import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/payment_repository.dart';
import 'package:splg_driver/services/trip_service.dart';

/// Cobro del pedido ya entregado: medio de pago, total a cobrar y detalle.
///
/// En efectivo el pago queda pendiente hasta que el chofer lo confirma:
/// "Pago recibido" llama al back y recién ahí sigue al cierre (si falla,
/// muestra el motivo y deja reintentar); "El cliente no pagó" pide una nota
/// opcional, avisa al back y sigue al cierre con un aviso. Con Mercado Pago lo
/// paga el cliente: se muestra el estado, sin esos botones.
class PaymentViewModel extends BaseViewModel {
  PaymentViewModel(
      {required this.orderId, TripService? trips, PaymentRepository? payments})
      : _tripsOverride = trips,
        _paymentsOverride = payments;

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

  /// Hay que cobrar en efectivo y todavía no está registrado.
  bool get needsCashConfirmation => isCash && !isPaid;

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

  /// "Pago recibido" (efectivo pendiente) o "Continuar" (ya pagado / online).
  Future<void> confirm() async {
    if (submitting) return;
    if (!needsCashConfirmation) {
      await _nav.replaceWithCompletedView(orderId: orderId);
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
      actionError =
          _text(e, 'No pudimos registrar el reporte. Probá de nuevo.');
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
