import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:uuid/uuid.dart';

import 'package:driver_mobile/app/app.locator.dart';
import 'package:driver_mobile/app/app.router.dart';
import 'package:driver_mobile/core/network/api_client.dart';
import 'package:driver_mobile/services/driver_auth_service.dart';
import 'package:driver_mobile/services/driver_socket_service.dart';
import 'package:driver_mobile/services/foreground_service.dart';
import 'package:driver_mobile/services/navigation_launcher.dart';

/// Cada cuánto se hace polling de `GET /orders/:id` mientras la entrega está
/// en curso, para enterarse de que el cliente confirmó la entrega escaneando
/// el QR (el chofer no tiene otro aviso: la confirmación la dispara el
/// cliente, no esta app).
const Duration _kPollInterval = Duration(seconds: 5);

/// ViewModel de la pantalla de entrega en curso: acompaña al pedido desde
/// `accepted` hasta `delivered`.
///
/// Nota sobre el `status` que viaja en las respuestas del backend: el estado
/// interno `ON_THE_WAY` del pedido se serializa como el string
/// `'out_for_delivery'` (ver `OrderMapper.mapStatus` en el backend y
/// `OrderStatus.outForDelivery` en `jennygas_lib`), mientras que el PATCH
/// para *fijar* ese estado espera literalmente `'on_the_way'` (el valor del
/// enum de la entidad). Por eso `markOnTheWay()` manda `'on_the_way'` pero
/// [isOnTheWay] compara contra `'out_for_delivery'`.
///
/// El parseo de la respuesta se hace a mano sobre el Map crudo (en vez de
/// `Order.fromJson` de `jennygas_lib`) porque el shape real que devuelve
/// `GET /orders/:id` no calza 1:1 con ese modelo compartido: `gas_cylinder`
/// no trae `isActive` (campo requerido, no nullable, en `GasCylinder`) y
/// `weight` viaja como número mientras el modelo lo tipa como `String`.
/// Usar `Order.fromJson` tal cual rompería esta pantalla con cualquier
/// pedido que tenga items. Queda como TODO para quien mantenga
/// `jennygas_lib` alinear ese modelo con `OrderResponseDto`.
class DeliveryViewModel extends BaseViewModel {
  DeliveryViewModel({required this.orderId});

  final String orderId;

  final _apiClient = ApiClient();
  final _navigationService = locator<NavigationService>();
  final _driverSocketService = locator<DriverSocketService>();
  final _foregroundService = locator<DriverForegroundService>();
  final _uuid = const Uuid();

  // Lazy a propósito, igual que en HomeViewModel: resolver DriverAuthService
  // dispara `FirebaseAuth.instance` en su constructor.
  DriverAuthService get _driverAuthService => locator<DriverAuthService>();

  Timer? _pollTimer;

  Map<String, dynamic>? _order;

  bool _updatingStatus = false;
  bool get isUpdatingStatus => _updatingStatus;

  bool _loadingQr = false;
  bool get isLoadingQr => _loadingQr;
  String? qrError;
  String? deliveryCode;

  /// El chofer ya avisó al cliente que llegó (CU-019). Es un flag local: el
  /// backend no cambia el estado del pedido, solo notifica al cliente.
  bool _arrivedNotified = false;
  bool get arrivedNotified => _arrivedNotified;

  /// Reporte de incidencia en curso (`POST /incidents`).
  bool _reportingIncident = false;
  bool get isReportingIncident => _reportingIncident;

  /// Calificación del cliente ya enviada (`POST /ratings`), una por pedido.
  bool _ratingSubmitted = false;
  bool get ratingSubmitted => _ratingSubmitted;
  bool _submittingRating = false;
  bool get isSubmittingRating => _submittingRating;
  String? ratingError;

  /// Mensaje de error de la última operación (carga, "en camino", nav). Se
  /// limpia al empezar una operación nueva.
  String? errorMessage;

  String? get status => _order?['status']?.toString();
  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isOnTheWay => status == 'out_for_delivery';
  bool get isDelivered => status == 'delivered';
  bool get isCancelled => status == 'cancelled';

  double get total {
    final value = _order?['total_amount'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  String? get paymentMethod => _order?['payment_method']?.toString();

  Map<String, dynamic>? get _address {
    final address = _order?['delivery_address'];
    return address is Map ? Map<String, dynamic>.from(address) : null;
  }

  /// Dirección lista para mostrar (calle + ciudad si está disponible).
  String get addressText {
    final address = _address;
    final street = address?['street']?.toString();
    if (street == null || street.isEmpty) return 'Dirección no disponible';
    final city = address?['city']?.toString();
    return (city != null && city.isNotEmpty) ? '$street, $city' : street;
  }

  double? get _lat => double.tryParse(_address?['latitude']?.toString() ?? '');
  double? get _lng => double.tryParse(_address?['longitude']?.toString() ?? '');

  bool get hasCoordinates => _lat != null && _lng != null;

  /// Items del pedido tal cual vienen de `order_items` (cada uno con
  /// `quantity` y `gas_cylinder`), listos para que la View los formatee.
  List<Map<String, dynamic>> get items {
    final raw = _order?['order_items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> initialize() async {
    setBusy(true);
    await _fetchOrder();
    setBusy(false);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrder({bool silent = false}) async {
    try {
      final token = await _driverAuthService.token;
      final response = await _apiClient.get('orders/$orderId', token);

      if (response.statusCode == 200 && response.data is Map) {
        final wasDelivered = isDelivered;
        _order = Map<String, dynamic>.from(response.data as Map);
        if (!silent) errorMessage = null;

        if (!wasDelivered && isDelivered) {
          _onDeliveryConfirmed();
        }
      } else if (!silent) {
        errorMessage =
            'No pudimos cargar el pedido (HTTP ${response.statusCode}).';
      }
    } catch (e) {
      debugPrint('Error trayendo el pedido $orderId: $e');
      if (!silent) errorMessage = 'Error de red al cargar el pedido.';
    }
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (isDelivered) return;

    _pollTimer = Timer.periodic(_kPollInterval, (_) {
      if (isDelivered) {
        _pollTimer?.cancel();
        return;
      }
      _fetchOrder(silent: true);
    });
  }

  /// El cliente confirmó la entrega (detectado vía polling): frena el
  /// broadcasting de GPS de esta entrega y revierte la notificación del
  /// foreground service a "en línea" (el chofer sigue conectado y disponible).
  void _onDeliveryConfirmed() {
    _pollTimer?.cancel();
    _driverSocketService.stopBroadcasting();
    _foregroundService.update(
      title: 'Estás en línea',
      text: 'Recibiendo pedidos cercanos',
    );
  }

  /// Avisa al cliente que el chofer llegó (CU-019). Requiere que el pedido esté
  /// "en camino"; el backend notifica al cliente (`order:arrived`) sin cambiar
  /// el estado del pedido.
  Future<void> markArrived() async {
    if (_arrivedNotified) return;
    final token = await _driverAuthService.token;
    if (token == null) {
      errorMessage = 'No se pudo avisar la llegada: falta la sesión.';
      notifyListeners();
      return;
    }
    try {
      final response = await _apiClient.patch(
        'orders/$orderId/arrived',
        const {},
        token,
        {'Idempotency-Key': _uuid.v4()},
      );
      if (response.statusCode == 200) {
        _arrivedNotified = true;
        errorMessage = null;
      } else {
        errorMessage =
            'No se pudo avisar la llegada (HTTP ${response.statusCode}).';
      }
    } catch (e) {
      debugPrint('Error avisando llegada del pedido $orderId: $e');
      errorMessage = 'Error de red al avisar la llegada.';
    }
    notifyListeners();
  }

  /// Reporta una incidencia de entrega (CU-024): `POST /incidents` con
  /// `{ orderId, type, description }`. `type` debe ser uno de los valores del
  /// enum del backend (`damaged` | `out_of_stock` | `no_show` | `other`).
  /// Devuelve `true` si el backend la registró.
  Future<bool> reportIncident({
    required String type,
    required String description,
  }) async {
    if (_reportingIncident) return false;

    final token = await _driverAuthService.token;
    if (token == null) {
      errorMessage = 'No se pudo reportar: falta la sesión.';
      notifyListeners();
      return false;
    }

    _reportingIncident = true;
    errorMessage = null;
    notifyListeners();

    var ok = false;
    try {
      final response = await _apiClient.post(
        'incidents',
        {'orderId': orderId, 'type': type, 'description': description},
        token,
        {'Idempotency-Key': _uuid.v4()},
      );
      ok = response.statusCode == 200 || response.statusCode == 201;
      if (!ok) {
        errorMessage =
            'No se pudo reportar la incidencia (HTTP ${response.statusCode}).';
      }
    } catch (e) {
      debugPrint('Error reportando incidencia del pedido $orderId: $e');
      errorMessage = 'Error de red al reportar la incidencia.';
    }

    _reportingIncident = false;
    notifyListeners();
    return ok;
  }

  /// Califica al cliente una vez entregado el pedido (CU-025): `POST /ratings`
  /// con `{ orderId, stars, comment? }`. El backend deriva a quién se califica
  /// desde el pedido y solo lo permite en pedidos `delivered`. Una sola vez por
  /// pedido y por lado.
  Future<bool> rateCustomer({required int stars, String? comment}) async {
    if (_submittingRating || _ratingSubmitted) return false;

    final token = await _driverAuthService.token;
    if (token == null) {
      ratingError = 'Falta la sesión para calificar.';
      notifyListeners();
      return false;
    }

    _submittingRating = true;
    ratingError = null;
    notifyListeners();

    var ok = false;
    try {
      final body = <String, dynamic>{'orderId': orderId, 'stars': stars};
      final trimmed = comment?.trim();
      if (trimmed != null && trimmed.isNotEmpty) body['comment'] = trimmed;

      final response = await _apiClient.post(
        'ratings',
        body,
        token,
        {'Idempotency-Key': _uuid.v4()},
      );
      ok = response.statusCode == 200 || response.statusCode == 201;
      if (ok) {
        _ratingSubmitted = true;
      } else {
        ratingError =
            'No se pudo enviar la calificación (HTTP ${response.statusCode}).';
      }
    } catch (e) {
      debugPrint('Error calificando al cliente en el pedido $orderId: $e');
      ratingError = 'Error de red al enviar la calificación.';
    }

    _submittingRating = false;
    notifyListeners();
    return ok;
  }

  /// Marca el pedido como "en camino" (`PATCH .../status {status: on_the_way}`)
  /// y asegura que el broadcasting de GPS de la entrega esté activo (por si
  /// esta pantalla se reabrió y el broadcasting no estaba corriendo, p.ej.
  /// tras reiniciar la app).
  Future<void> markOnTheWay() async {
    if (_updatingStatus) return;

    final token = await _driverAuthService.token;
    final userId = _driverAuthService.userId;
    if (token == null || userId == null) {
      errorMessage = 'No se pudo actualizar: falta la sesión.';
      notifyListeners();
      return;
    }

    _updatingStatus = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.patch(
        'orders/$orderId/status',
        {'status': 'on_the_way'},
        token,
        {'Idempotency-Key': _uuid.v4()},
      );

      if (response.statusCode == 200) {
        debugPrint('Pedido $orderId en camino');
        _driverSocketService.startBroadcasting(orderId, userId, token);
        await _fetchOrder();
      } else {
        errorMessage =
            'No se pudo marcar "en camino" (HTTP ${response.statusCode}).';
      }
    } catch (e) {
      debugPrint('Error marcando en camino el pedido $orderId: $e');
      errorMessage = 'Error de red al marcar "en camino".';
    }

    _updatingStatus = false;
    notifyListeners();
  }

  /// Trae (una sola vez) el código secreto de entrega para renderizar el QR.
  Future<void> showDeliveryCode() async {
    if (deliveryCode != null || _loadingQr) return;

    _loadingQr = true;
    qrError = null;
    notifyListeners();

    try {
      final token = await _driverAuthService.token;
      final response =
          await _apiClient.get('orders/$orderId/delivery-code', token);

      if (response.statusCode == 200 && response.data is Map) {
        deliveryCode = response.data['deliveryCode']?.toString();
        if (deliveryCode == null || deliveryCode!.isEmpty) {
          qrError = 'El pedido no tiene código de entrega todavía.';
        }
      } else {
        qrError = 'No se pudo obtener el código de entrega '
            '(HTTP ${response.statusCode}).';
      }
    } catch (e) {
      debugPrint('Error trayendo el código de entrega de $orderId: $e');
      qrError = 'Error de red al obtener el código de entrega.';
    }

    _loadingQr = false;
    notifyListeners();
  }

  Future<void> openWaze() async {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) {
      errorMessage = 'No hay coordenadas de entrega para navegar.';
      notifyListeners();
      return;
    }
    await NavigationLauncher.openWaze(lat, lng);
  }

  Future<void> openGoogleMaps() async {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) {
      errorMessage = 'No hay coordenadas de entrega para navegar.';
      notifyListeners();
      return;
    }
    await NavigationLauncher.openGoogleMaps(lat, lng);
  }

  /// Vuelve al Home una vez confirmada la entrega (o si el chofer decide
  /// salir de la pantalla).
  Future<void> goHome() async {
    await _navigationService.clearStackAndShow(Routes.homeView);
  }
}
