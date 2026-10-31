import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/trip_service.dart';

/// Resultado de aceptar en el back desde la oferta.
enum AcceptOutcome { accepted, refused, unknown }

/// Datos de la oferta de pedido (cuenta regresiva y detalle).
///
/// El back ofrece cada pedido a un chofer por una ventana acotada
/// (`OFFER_TTL_SECONDS`, 30 s) y, si no responde, lo re-ofrece al siguiente. El
/// payload del socket trae `expiresAt`; este modelo cuenta hasta ahí y, si el
/// chofer no decide a tiempo, descarta la oferta sola (equivale a rechazar).
///
/// El payload sólo trae monto, medio de pago y vencimiento: el cliente, la
/// dirección y las garrafas se leen de `GET /orders/:id`.
class OrderOfferDialogModel extends BaseViewModel {
  OrderOfferDialogModel({TripService? trips}) : _tripsOverride = trips;

  final TripService? _tripsOverride;
  TripService get _trips => _tripsOverride ?? locator<TripService>();

  Timer? _timer;
  int _remainingSeconds = 0;
  int get remainingSeconds => _remainingSeconds;

  int _totalSeconds = 30;

  /// Segundos con los que arrancó la cuenta (el 100 % de la barra).
  int get totalSeconds => _totalSeconds;

  /// Guarda contra disparar el vencimiento más de una vez (o después de que el
  /// chofer ya aceptó/rechazó a mano).
  bool _finished = false;
  bool get isFinished => _finished;

  /// Ya se tocó «Aceptar»: protege contra un segundo toque mientras el back
  /// responde.
  bool _accepting = false;
  bool get isAccepting => _accepting;

  /// Texto del error de la aceptación (el back la rechazó o falta el pedido).
  String? acceptError;

  /// Acepta el pedido en el back ANTES de que el chofer elija mapa: la oferta
  /// vence en el servidor y la cuenta sólo se frena acá. Detiene la cuenta al
  /// instante. [AcceptOutcome.refused]: el back respondió que no (409, 403…),
  /// no se insiste. [AcceptOutcome.unknown]: sin respuesta; el Inicio verifica
  /// y reintenta con la misma clave de idempotencia.
  Future<AcceptOutcome> acceptInBackend(String orderId) async {
    if (_accepting) return AcceptOutcome.unknown;
    _accepting = true;
    stop();
    notifyListeners();
    try {
      await _trips.setStatus(orderId, 'accepted');
      return AcceptOutcome.accepted;
    } catch (e) {
      debugPrint('No se pudo aceptar $orderId desde la oferta: $e');
      if (e is DioException && e.response != null) {
        acceptError = DriverApiService.errorMessage(e);
        return AcceptOutcome.refused;
      }
      return AcceptOutcome.unknown;
    }
  }

  /// Falta el pedido en el aviso: no hay nada que aceptar. Se avisa en pantalla
  /// y el chofer puede volver.
  void missingOrder() {
    acceptError = 'No pudimos identificar el pedido. Tocá Volver.';
    notifyListeners();
  }

  TripOrder? order;
  RatingSummary? customerRating;
  String? loadError;
  bool loading = false;

  /// Lee el pedido y la calificación del cliente. Un error no impide decidir.
  Future<void> load(String orderId) async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      order = await _trips.order(orderId);
      final customerId = order?.customerId;
      if (customerId != null) {
        customerRating = await _trips.customerRating(customerId);
      }
    } catch (e) {
      loadError = e is DioException
          ? ApiErrorText.of(e.response?.statusCode, e.response?.data)
          : 'No pudimos cargar los datos del pedido.';
    }
    loading = false;
    notifyListeners();
  }

  /// Arranca la cuenta regresiva hasta `expiresAt` (ISO-8601 string o millis
  /// epoch). Si no hay un valor válido, cae a [fallbackSeconds]. Al llegar a 0
  /// invoca [onExpired] una única vez.
  void start(
    dynamic expiresAt,
    VoidCallback onExpired, {
    int fallbackSeconds = 30,
  }) {
    _remainingSeconds = _secondsUntil(expiresAt, fallbackSeconds);
    _totalSeconds = _remainingSeconds < 1 ? 1 : _remainingSeconds;
    notifyListeners();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _remainingSeconds--;
      if (_remainingSeconds <= 0 && !_finished) {
        _finished = true;
        _timer?.cancel();
        onExpired();
      }
      notifyListeners();
    });
  }

  /// El chofer decidió a mano (aceptar/rechazar): frena el timer para que no
  /// dispare el vencimiento encima de la decisión.
  void stop() {
    _finished = true;
    _timer?.cancel();
  }

  int _secondsUntil(dynamic expiresAt, int fallback) {
    DateTime? deadline;
    if (expiresAt is String) {
      deadline = DateTime.tryParse(expiresAt);
    } else if (expiresAt is int) {
      deadline = DateTime.fromMillisecondsSinceEpoch(expiresAt);
    }
    if (deadline == null) return fallback;

    final secs = deadline.toLocal().difference(DateTime.now()).inSeconds;
    // Si ya viene vencido o con un desfasaje raro de reloj, usamos el fallback
    // en vez de descartar la oferta al instante. Tope de 120s por las dudas.
    if (secs <= 0) return fallback;
    return secs > 120 ? 120 : secs;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
