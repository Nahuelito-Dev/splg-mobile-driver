import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/current_position.dart';
import 'package:splg_driver/services/delivery_offer_slot.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/common/navigation_helpers.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart'
    show kArrivalPositionMaxAge, kArrivalPositionTimeout, noLocationText;
import 'package:splg_driver/ui/views/delivery_code/offer_slot_host.dart';

/// Cada cuánto se revisa que el pedido siga siendo del chofer (cancelación o
/// liberación mientras escribe el código).
const Duration kCodePollInterval = Duration(seconds: 3);

/// Largo del código de entrega.
const int kDeliveryCodeLength = 6;

const String kCodeIncorrectText = 'El código no es correcto.';
const String kCodeFormatText = 'El código tiene que ser de 6 dígitos.';
const String kCodeBlockedText =
    'Pedile al cliente que genere un código nuevo en su app o comunicate con '
    'la distribuidora.';
const String kOrderNotOnTheWayText = 'El pedido ya no está en camino.';
const String kNotYourOrderText = 'Este pedido no está asignado a vos.';

/// «Pedile el código al cliente»: el chofer escribe los 6 dígitos que le dicta
/// el cliente y la app los manda con la ubicación actual
/// (`POST /api/v3/orders/:id/confirm-delivery`). Con 200 (también si ya estaba
/// entregado) sigue con el cobro. Un rechazo del back se muestra; nunca se toma
/// como entrega hecha.
class DeliveryCodeViewModel extends BaseViewModel with OfferSlotHost {
  DeliveryCodeViewModel({
    required this.orderId,
    TripService? trips,
    this.pollInterval = kCodePollInterval,
    void Function()? goHome,
    DeliveryOfferSlot? offers,
    LocationService? location,
    DateTime Function()? clock,
    this.positionMaxAge = kArrivalPositionMaxAge,
    this.positionTimeout = kArrivalPositionTimeout,
  })  : _tripsOverride = trips,
        _goHome = goHome ?? popToHome,
        _offersOverride = offers,
        _locationOverride = location,
        _clock = clock ?? DateTime.now;

  final String orderId;
  final Duration pollInterval;
  final Duration positionMaxAge;
  final Duration positionTimeout;
  final TripService? _tripsOverride;
  final void Function() _goHome;
  final LocationService? _locationOverride;
  final DateTime Function() _clock;

  final DeliveryOfferSlot? _offersOverride;
  @override
  DeliveryOfferSlot? get offerSlotOverride => _offersOverride;

  TripService get _trips => _tripsOverride ?? locator<TripService>();
  LocationService get _location =>
      _locationOverride ?? locator<LocationService>();
  final _nav = locator<NavigationService>();
  final _dialogs = locator<DialogService>();
  DriverSocketService get _socket => locator<DriverSocketService>();

  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _cancelSub;
  bool _disposed = false;
  bool _closing = false;
  bool _checking = false;

  TripOrder? order;
  String? loadError;

  /// Dígitos escritos (0 a 6).
  String digits = '';

  /// Mensaje del último rechazo o fallo (null = ninguno).
  String? errorMessage;

  /// El back bloqueó el código por demasiados errores: hay que pedirle al cliente
  /// uno nuevo; escribir no sirve hasta entonces.
  bool blocked = false;

  bool _sending = false;
  bool get sending => _sending;

  bool get complete => digits.length == kDeliveryCodeLength;
  bool get canSubmit => complete && !_sending && !blocked;

  /// «123 456» para leerlo en voz alta (lector de pantalla).
  String get spokenDigits => digits.split('').join(' ');

  void addDigit(String d) {
    if (_sending || blocked || digits.length >= kDeliveryCodeLength) return;
    if (!RegExp(r'^\d$').hasMatch(d)) return;
    digits += d;
    errorMessage = null;
    rebuildUi();
  }

  void deleteDigit() {
    if (_sending || digits.isEmpty) return;
    digits = digits.substring(0, digits.length - 1);
    errorMessage = null;
    rebuildUi();
  }

  Future<void> initialize() async {
    hostOffers();
    _cancelSub = _socket.orderCancelled.listen((p) {
      if (p['orderId']?.toString() == orderId) _check();
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
    } catch (e) {
      if (isOrderGone(e, known: order != null) && !_closing) {
        setBusy(false);
        await _lost(false);
        return;
      }
      loadError = e is DioException
          ? actionErrorText(e)
          : 'No pudimos cargar el pedido.';
    }
    setBusy(false);
    if (loadError == null) _startPolling();
  }

  /// «Confirmar entrega»: lee la ubicación y manda código + posición.
  Future<void> submit() async {
    if (!canSubmit) return;
    _sending = true;
    errorMessage = null;
    rebuildUi();
    try {
      final read = await readCurrentPosition(
        _location,
        maxAge: positionMaxAge,
        timeout: positionTimeout,
        clock: _clock,
        isCancelled: () => _disposed,
      );
      if (_disposed) return;
      final here = read.position;
      if (here == null) {
        await _failNoLocation(read.block ?? LocationBlock.unreadable);
        return;
      }
      await _trips.confirmDelivery(
        orderId,
        code: digits,
        latitude: here.latitude,
        longitude: here.longitude,
        accuracyMeters: here.accuracy > 0 ? here.accuracy : null,
      );
      _sending = false;
      if (_disposed) return;
      rebuildUi();
      await _delivered();
      return;
    } catch (e) {
      debugPrint('Confirmar entrega de $orderId falló: $e');
      _applyFailure(e);
    }
    _sending = false;
    if (!_disposed) rebuildUi();
  }

  void _applyFailure(Object e) {
    if (e is! DioException) {
      errorMessage = e is StateError
          ? e.message
          : 'No pudimos confirmar la entrega. Probá de nuevo.';
      return;
    }
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final code = data is Map ? data['code']?.toString() : null;
    switch ((status, code)) {
      case (400, 'DELIVERY_CODE_INCORRECTO'):
        errorMessage = _incorrectText(data);
        digits = '';
      case (400, 'DELIVERY_CODE_FORMATO'):
        errorMessage = kCodeFormatText;
        digits = '';
      case (409, 'DELIVERY_CODE_BLOQUEADO'):
        blocked = true;
        errorMessage = kCodeBlockedText;
      case (409, 'ORDER_NOT_ON_THE_WAY'):
        errorMessage = kOrderNotOnTheWayText;
        // Puede estar entregado (sigue con el cobro) o cancelado (aviso).
        unawaited(_check());
      case (403, _):
        errorMessage = kNotYourOrderText;
      default:
        errorMessage = actionErrorText(e);
    }
  }

  /// «El código no es correcto. Te quedan N intentos.» si el back informa los
  /// intentos que faltan (`remaining`); si no, sólo el primer renglón.
  String _incorrectText(Object? data) {
    final r =
        data is Map ? (data['remaining'] ?? data['attemptsRemaining']) : null;
    if (r is! num) return kCodeIncorrectText;
    final n = r.toInt();
    if (n <= 0) return kCodeIncorrectText;
    return '$kCodeIncorrectText Te ${n == 1 ? 'queda 1 intento' : 'quedan $n intentos'}.';
  }

  /// Sin ubicación no se manda. Con el permiso bloqueado para siempre, además
  /// se ofrece abrir los ajustes de la app.
  Future<void> _failNoLocation(LocationBlock block) async {
    final text = noLocationText(block);
    errorMessage = text;
    _sending = false;
    rebuildUi();
    if (block != LocationBlock.permissionPermanentlyDenied || _disposed) return;
    final response = await _dialogs.showDialog(
      title: 'Ubicación bloqueada',
      description: text,
      buttonTitle: 'Abrir Ajustes',
      cancelTitle: 'Ahora no',
    );
    if (response?.confirmed == true) await _location.openDeviceSettings();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _check());
  }

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
      }
    } catch (e) {
      if (isOrderGone(e, known: order != null) && !_disposed && !_closing) {
        await _lost(false);
      }
      // Otro fallo (sin red): el próximo ciclo reintenta.
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
    // marca en el momento, antes de que retome, y sólo si el cobro quedó arriba.
    if (openPaymentView(_nav, orderId)) {
      _trips.paymentOpenedFor = orderId;
      return;
    }
    // No se abrió el cobro: se sigue acá y el próximo sondeo lo reintenta.
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

  /// «Volver»: deja de sondear antes de salir.
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
    releaseOffers();
    super.dispose();
  }
}
