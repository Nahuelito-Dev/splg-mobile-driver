import 'dart:async';

import 'package:dio/dio.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/common/navigation_helpers.dart';

/// Cada cuánto se pregunta si el cliente ya confirmó la entrega.
const Duration kQrPollInterval = Duration(seconds: 3);

/// "Finalización": el chofer MUESTRA el QR (`GET /orders/:id/delivery-code`) y
/// el cliente lo escanea (`POST /orders/:id/confirm-delivery`, sólo cliente o
/// admin). Esta pantalla espera la confirmación releyendo el pedido; al pasar a
/// `delivered` sigue con el cobro.
///
/// El back no deja confirmar la entrega al chofer por el camino del QR y el
/// QR es justamente la prueba anti-fraude, por eso no hay opción "sin QR".
class DeliveryQrViewModel extends BaseViewModel {
  DeliveryQrViewModel({
    required this.orderId,
    TripService? trips,
    this.pollInterval = kQrPollInterval,
    void Function()? goHome,
  })  : _tripsOverride = trips,
        _goHome = goHome ?? popToHome;

  final String orderId;
  final Duration pollInterval;
  final TripService? _tripsOverride;
  final void Function() _goHome;

  TripService get _trips => _tripsOverride ?? locator<TripService>();
  final _nav = locator<NavigationService>();
  final _dialogs = locator<DialogService>();
  DriverSocketService get _socket => locator<DriverSocketService>();

  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _cancelSub;
  bool _disposed = false;
  bool _closing = false;

  String? code;
  TripOrder? order;
  String? loadError;

  Future<void> initialize() async {
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
      code = await _trips.deliveryCode(orderId);
    } catch (e) {
      loadError = _text(e);
    }
    setBusy(false);
    if (code != null) _startPolling();
  }

  String _text(Object e) => e is DioException
      ? ApiErrorText.of(e.response?.statusCode, e.response?.data)
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
      }
    } catch (_) {
      // Sin red: se sigue esperando, el próximo ciclo reintenta.
    } finally {
      _checking = false;
    }
  }

  Future<void> _delivered() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _socket.stopTracking();
    await _nav.replaceWithPaymentView(orderId: orderId);
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

  void back() => _nav.back();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cancelSub?.cancel();
    super.dispose();
  }
}
