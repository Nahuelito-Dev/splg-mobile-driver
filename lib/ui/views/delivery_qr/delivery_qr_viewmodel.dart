import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/delivery_offer_slot.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/common/navigation_helpers.dart';
import 'package:splg_driver/ui/views/delivery_qr/offer_slot_host.dart';

/// Cada cuánto se pregunta si el cliente ya confirmó la entrega.
const Duration kQrPollInterval = Duration(seconds: 3);

/// "Finalización": el chofer MUESTRA el QR (`GET /orders/:id/delivery-code`) y
/// el cliente lo escanea (`POST /orders/:id/confirm-delivery`, sólo cliente o
/// admin). Esta pantalla espera la confirmación releyendo el pedido; al pasar a
/// `delivered` sigue con el cobro.
///
/// El back no deja confirmar la entrega al chofer por el camino del QR y el
/// QR es justamente la prueba anti-fraude, por eso no hay opción "sin QR".
class DeliveryQrViewModel extends BaseViewModel with OfferSlotHost {
  DeliveryQrViewModel({
    required this.orderId,
    TripService? trips,
    this.pollInterval = kQrPollInterval,
    void Function()? goHome,
    DeliveryOfferSlot? offers,
  })  : _tripsOverride = trips,
        _goHome = goHome ?? popToHome,
        _offersOverride = offers;

  final String orderId;
  final Duration pollInterval;
  final TripService? _tripsOverride;
  final void Function() _goHome;

  /// Las ofertas que llegan con el QR arriba se muestran en una banda de esta
  /// pantalla, sin taparlo.
  final DeliveryOfferSlot? _offersOverride;
  @override
  DeliveryOfferSlot? get offerSlotOverride => _offersOverride;

  TripService get _trips => _tripsOverride ?? locator<TripService>();
  final _nav = locator<NavigationService>();
  final _dialogs = locator<DialogService>();
  DriverSocketService get _socket => locator<DriverSocketService>();

  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _cancelSub;
  StreamSubscription<Map<String, dynamic>>? _codeSub;
  bool _disposed = false;
  bool _closing = false;

  String? code;
  TripOrder? order;
  String? loadError;

  /// El código para leer en voz alta: «123 456» si son 6 dígitos; un código
  /// viejo (10 hexadecimales) se muestra tal cual.
  static String formatCode(String code) => RegExp(r'^\d{6}$').hasMatch(code)
      ? '${code.substring(0, 3)} ${code.substring(3)}'
      : code;

  String? get displayCode => code == null ? null : formatCode(code!);

  /// Desde cuántos errores del cliente se avisa, antes del bloqueo.
  static const int kWarnFromAttempts = 3;

  /// Códigos incorrectos del cliente desde el último código nuevo.
  int attempts = 0;

  /// El cliente agotó los intentos: el QR ya no sirve hasta generar uno nuevo.
  bool blocked = false;

  /// Aviso suave del 3.er error en adelante, mientras no esté bloqueado.
  bool get showAttemptsWarning => !blocked && attempts >= kWarnFromAttempts;

  /// Tope de intentos del back; el aviso del socket lo informa.
  int maxAttempts = 5;

  /// Cambia con cada novedad del código (aviso, regeneración): una lectura del
  /// sondeo iniciada antes de la última novedad ya es vieja y se descarta.
  int _codeGeneration = 0;

  void _applyAttempts(int n, bool isBlocked) {
    _codeGeneration++;
    attempts = n > maxAttempts ? maxAttempts : n;
    blocked = isBlocked;
    if (isBlocked) confirmingRegenerate = false;
  }

  /// true mientras se le pide confirmación al chofer para cambiar el código.
  bool confirmingRegenerate = false;
  String? regenerateError;
  bool _regenerating = false;
  bool get regenerating => _regenerating;

  void askRegenerate() {
    // Bloqueado, el código actual ya no sirve: no hace falta confirmar.
    if (blocked) {
      regenerateCode();
      return;
    }
    confirmingRegenerate = true;
    regenerateError = null;
    rebuildUi();
  }

  void cancelRegenerate() {
    confirmingRegenerate = false;
    rebuildUi();
  }

  /// Pide un código nuevo al back y lo muestra al instante (QR incluido). Si
  /// falla, deja el actual y muestra el motivo.
  Future<void> regenerateCode() async {
    if (_regenerating) return;
    _regenerating = true;
    _codeGeneration++;
    regenerateError = null;
    rebuildUi();
    try {
      code = await _trips.regenerateDeliveryCode(orderId);
      _applyAttempts(0, false);
      confirmingRegenerate = false;
    } catch (e) {
      regenerateError = _text(e);
    }
    _codeGeneration++;
    _regenerating = false;
    if (!_disposed) rebuildUi();
  }

  Future<void> initialize() async {
    hostOffers();
    _cancelSub = _socket.orderCancelled.listen((p) {
      if (p['orderId']?.toString() == orderId) _check();
    });
    _codeSub = _socket.deliveryCodeFailed.listen((p) {
      if (p['orderId']?.toString() != orderId || _disposed) return;
      final n = p['attempts'];
      final max = p['maxAttempts'];
      if (max is num && max > 0) maxAttempts = max.toInt();
      _applyAttempts(n is num ? n.toInt() : attempts + 1, p['blocked'] == true);
      rebuildUi();
    });
    await load();
  }

  Future<void> load() async {
    loadError = null;
    setBusy(true);
    try {
      order = await _trips.order(orderId);
      if (order!.status == DriverOrderStatus.delivered) {
        setBusy(false);
        await _delivered();
        return;
      }
      final generation = _codeGeneration;
      final info = await _trips.deliveryCode(orderId);
      // Un aviso o una regeneración que llegó mientras tanto es más nuevo.
      if (generation == _codeGeneration) {
        _applyInfo(info);
      } else {
        code ??= info.code;
      }
    } catch (e) {
      if (isOrderGone(e, known: order != null) && !_closing) {
        setBusy(false);
        await _lost(false);
        return;
      }
      loadError = _text(e);
    }
    setBusy(false);
    if (code != null) _startPolling();
  }

  void _applyInfo(DeliveryCodeInfo info) {
    code = info.code;
    _applyAttempts(info.attempts, info.blocked);
  }

  String _text(Object e) => e is DioException
      ? actionErrorText(e)
      : (e is StateError ? e.message : 'No pudimos cargar el código.');

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _check());
  }

  bool _checking = false;

  Future<void> _check() async {
    if (_checking || _closing || _disposed) return;
    _checking = true;
    try {
      final fresh = await _trips.order(orderId);
      if (_disposed || _closing) return;
      order = fresh;
      if (fresh.status == DriverOrderStatus.delivered) {
        await _delivered();
      } else if (fresh.status == DriverOrderStatus.cancelled ||
          fresh.status == DriverOrderStatus.pending ||
          fresh.status == DriverOrderStatus.reserved) {
        await _lost(fresh.status == DriverOrderStatus.cancelled);
      } else if (!_regenerating) {
        // Red de seguridad si el socket perdió un aviso de intentos.
        final generation = _codeGeneration;
        final info = await _trips.deliveryCode(orderId);
        if (_disposed || _closing || _regenerating) return;
        if (generation != _codeGeneration) return;
        _applyInfo(info);
        rebuildUi();
      }
    } catch (e) {
      if (isOrderGone(e, known: order != null) && !_disposed && !_closing) {
        await _lost(false);
      }
      // Otro fallo (sin red): se sigue esperando, el próximo ciclo reintenta.
    } finally {
      _checking = false;
    }
  }

  Future<void> _delivered() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _socket.stopTracking();
    // La pantalla del pedido (abajo) retoma apenas esta ruta se reemplaza: se
    // marca en el momento, antes de que retome, y sólo si el cobro quedó
    // arriba.
    if (openPaymentView(_nav, orderId)) {
      _trips.paymentOpenedFor = orderId;
      return;
    }
    // No se abrió el cobro: no queda marcado y se sigue esperando aquí (el
    // próximo sondeo lo vuelve a intentar).
    debugPrint('El cobro de $orderId no quedó abierto: se reintenta');
    _closing = false;
    if (!_disposed) _startPolling();
  }

  Future<void> _lost(bool cancelled) async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _socket.stopTracking();
    await _dialogs.showDialog(
      title: cancelled ? 'Pedido cancelado' : 'Pedido liberado',
      description: cancelled
          ? 'El pedido fue cancelado. Seguís en línea para recibir otros.'
          : 'El pedido ya no está asignado a vos. Seguís en línea para recibir otros.',
    );
    _trips.endFlow();
    _goHome();
  }

  /// «Volver»: deja de sondear antes de salir; mientras la ruta se va, la
  /// pantalla del pedido ya retomó el control.
  void back() {
    _closing = true;
    _timer?.cancel();
    _nav.back();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cancelSub?.cancel();
    _codeSub?.cancel();
    releaseOffers();
    super.dispose();
  }
}
