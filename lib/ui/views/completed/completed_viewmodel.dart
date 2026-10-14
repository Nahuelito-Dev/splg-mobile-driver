import 'package:dio/dio.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/common/navigation_helpers.dart';

/// Cierre del pedido: "¡Pedido completado!" y la calificación del cliente
/// (`POST /ratings`, una por pedido y por lado). Al terminar deja anotado lo
/// ganado para el cartel "¡Ganaste!" del Inicio y vuelve a él.
class CompletedViewModel extends BaseViewModel {
  CompletedViewModel(
      {required this.orderId,
      TripService? trips,
      void Function()? goHome,
      this.paid = false})
      : _tripsOverride = trips,
        _goHome = goHome ?? popToHome;

  /// El back confirmó el cobro en efectivo en el paso anterior.
  final bool paid;

  final String orderId;
  final TripService? _tripsOverride;
  final void Function() _goHome;
  TripService get _trips => _tripsOverride ?? locator<TripService>();

  TripOrder? order;
  RatingSummary? customerRating;

  int stars = 0;
  String comment = '';
  bool submitting = false;
  bool rated = false;
  String? ratingError;

  Future<void> load() async {
    try {
      order = await _trips.order(orderId);
      final cid = order?.customerId;
      if (cid != null) customerRating = await _trips.customerRating(cid);
    } catch (_) {
      // Se puede calificar igual: el pedido se identifica por id.
    }
    notifyListeners();
  }

  void setStars(int v) {
    stars = v;
    ratingError = null;
    notifyListeners();
  }

  void setComment(String v) => comment = v;

  /// Envía la calificación. `true` si el back la aceptó o ya existía una.
  Future<bool> submitRating() async {
    if (submitting || rated) return rated;
    if (stars < 1) {
      ratingError = 'Elegí de 1 a 5 estrellas.';
      notifyListeners();
      return false;
    }
    submitting = true;
    ratingError = null;
    notifyListeners();
    try {
      await _trips.rateCustomer(orderId, stars, comment);
      rated = true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409 &&
          !ApiErrorText.isInProgress(409, e.response?.data)) {
        // Ya estaba calificado: no hay nada más que hacer acá.
        rated = true;
      } else {
        ratingError = ApiErrorText.of(e.response?.statusCode, e.response?.data);
      }
    } catch (_) {
      ratingError = ApiErrorText.generic;
    }
    submitting = false;
    notifyListeners();
    return rated;
  }

  /// Cierra el pedido y vuelve al Inicio con el cartel "¡Ganaste!".
  void finish() {
    // "¡Ganaste!" cuenta sólo lo efectivamente cobrado.
    final collected = paid || (order?.isPaid ?? false);
    _trips.endFlow(earned: collected ? order?.amountToCollect : null);
    _goHome();
  }
}
