import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stacked/stacked.dart';

/// Maneja la cuenta regresiva de la oferta de pedido.
///
/// El backend ofrece cada pedido a un chofer por una ventana acotada
/// (`OFFER_TTL_SECONDS`, 30s) y, si no responde, lo re-ofrece al siguiente.
/// El payload trae `expiresAt`; este modelo cuenta hasta ahí y, si el chofer
/// no decide a tiempo, descarta la oferta solo (equivale a rechazar) para no
/// dejar en pantalla un pedido que el backend ya pasó a otro. También expone
/// los segundos restantes para pintarlos en el botón.
class OrderOfferDialogModel extends BaseViewModel {
  Timer? _timer;
  int _remainingSeconds = 0;
  int get remainingSeconds => _remainingSeconds;

  /// Guarda contra disparar el vencimiento más de una vez (o después de que el
  /// chofer ya aceptó/rechazó a mano).
  bool _finished = false;

  /// Arranca la cuenta regresiva hasta `expiresAt` (ISO-8601 string o millis
  /// epoch). Si no hay un valor válido, cae a [fallbackSeconds]. Al llegar a 0
  /// invoca [onExpired] una única vez.
  void start(
    dynamic expiresAt,
    VoidCallback onExpired, {
    int fallbackSeconds = 30,
  }) {
    _remainingSeconds = _secondsUntil(expiresAt, fallbackSeconds);
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
