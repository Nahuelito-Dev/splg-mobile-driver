import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/backend_route_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/recovery_repository.dart';
import 'package:splg_driver/services/route_batch_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/common/navigation_helpers.dart';
import 'package:splg_driver/ui/common/pickups_model.dart';

/// Cada cuánto se relee `GET /orders/:id` mientras el pedido está en curso, para
/// enterarse de que lo cancelaron o lo liberaron desde otro lado.
const Duration kTripPollInterval = Duration(seconds: 5);

/// Antigüedad máxima de la última posición del stream para mandarla con
/// «Llegué»; si es más vieja se pide una lectura nueva del GPS.
const Duration kArrivalPositionMaxAge = Duration(seconds: 30);

/// Lo que se espera la lectura nueva del GPS antes de dar la ubicación por no
/// disponible.
const Duration kArrivalPositionTimeout = Duration(seconds: 6);

/// Lo que ve el chofer si no hay ubicación para mandar con «Llegué», según
/// el motivo.
const String kGpsOffText = 'Tenés el GPS apagado. Activalo y probá de nuevo.';
const String kLocationPermissionText =
    'La app no tiene permiso para usar tu ubicación. Permitilo y probá de nuevo.';
const String kLocationPermanentlyDeniedText =
    'La ubicación está bloqueada para la app. Habilitala en Ajustes y probá '
    'de nuevo.';
const String kLocationUnreadableText =
    'No pudimos leer tu ubicación a tiempo. Esperá unos segundos y probá de '
    'nuevo.';

String noLocationText(LocationBlock block) => switch (block) {
      LocationBlock.serviceDisabled => kGpsOffText,
      LocationBlock.permissionDenied => kLocationPermissionText,
      LocationBlock.permissionPermanentlyDenied =>
        kLocationPermanentlyDeniedText,
      LocationBlock.unreadable => kLocationUnreadableText,
    };

/// Cada cuánto se relee la lista de retiros de envases mientras dura el viaje.
const Duration kPickupsRefresh = Duration(seconds: 30);

/// Vacías de un tipo de garrafa en la entrega: las que el cliente tiene que
/// devolver por el canje y las que el chofer dice que recibió.
@immutable
class EmptiesRow {
  const EmptiesRow({
    required this.gasCylinderId,
    required this.label,
    required this.expected,
    required this.purchased,
    required this.declared,
    required this.value,
  });

  final String gasCylinderId;
  final String label;

  /// Vacías esperadas (cantidad menos envases comprados).
  final int expected;

  /// Envases que el cliente compró: por esos no devuelve vacía.
  final int purchased;

  /// Lo que el back tiene registrado (las declaradas o, si no hay, las
  /// esperadas).
  final int declared;

  /// Lo que marca el selector «Te dio».
  final int value;

  bool get changed => value != declared;
  bool get canAdd => value < expected;
  bool get canRemove => value > 0;

  /// «El cliente compró 2 envases: no devuelve vacía por esos.»; null si no
  /// compró ninguno.
  String? get purchasedText => purchased <= 0
      ? null
      : purchased == 1
          ? 'El cliente compró 1 envase: no devuelve vacía por ese.'
          : 'El cliente compró $purchased envases: no devuelve vacía por esos.';
}

/// Pantalla del pedido en curso: desde que el chofer lo acepta hasta que sale
/// hacia el cliente y llega ("Pedido aceptado" y "En camino"). La entrega con
/// QR, el cobro y la calificación son pantallas siguientes.
///
/// Máquina de estados del back (`order-status.machine.ts`):
/// `accepted -> on_the_way -> delivered`; el chofer sólo mueve `accepted` y
/// `on_the_way`, la entrega la confirma el cliente escaneando el QR. Si el
/// pedido vuelve a `pending`/`reserved` o pasa a `cancelled` se corta el
/// reparto y se avisa.
class DeliveryViewModel extends BaseViewModel {
  DeliveryViewModel({
    required this.orderId,
    TripService? trips,
    this.pollInterval = kTripPollInterval,
    void Function()? goHome,
    SplgRouteService? routes,
    Future<Response<dynamic>> Function(String path, String token)? routeGet,
    this.noPositionRetry = const Duration(seconds: 3),
    Future<BitmapDescriptor?> Function()? iconLoader,
    RecoveryRepository? recovery,
    RouteBatchRepository? batches,
    this.arrivalPositionMaxAge = kArrivalPositionMaxAge,
    this.arrivalPositionTimeout = kArrivalPositionTimeout,
    DateTime Function()? clock,
  })  : _tripsOverride = trips,
        _clock = clock ?? DateTime.now,
        _batchesOverride = batches,
        pickups = PickupsModel(orderId: orderId, repo: recovery),
        _routeGet = routeGet,
        _goHome = goHome ?? popToHome,
        _routesOverride = routes,
        _iconLoader = iconLoader;

  final String orderId;
  final Duration pollInterval;

  /// Ver [kArrivalPositionMaxAge] y [kArrivalPositionTimeout].
  final Duration arrivalPositionMaxAge;
  final Duration arrivalPositionTimeout;
  final DateTime Function() _clock;

  /// Envases que el cliente aceptó devolver en este pedido (CU-108).
  final PickupsModel pickups;

  /// Espera antes de volver a pedir la ruta cuando el back todavía no tiene la
  /// posición del chofer (409).
  final Duration noPositionRetry;
  final TripService? _tripsOverride;
  final void Function() _goHome;
  final SplgRouteService? _routesOverride;
  final Future<Response<dynamic>> Function(String path, String token)?
      _routeGet;
  final Future<BitmapDescriptor?> Function()? _iconLoader;

  late final SplgRouteService _routes = _routesOverride ??
      BackendRouteService(
        orderId: orderId,
        tokenProvider: () => locator<DriverAuthService>().token,
        get: _routeGet,
        canRequest: () => isAccepted || isOnTheWay,
      );

  Future<void> _loadVehicleIcon() async {
    try {
      final loader = _iconLoader ??
          () => SplgVehicleIcon.descriptor(body: AppColors.llama600);
      final icon = await loader();
      if (_disposed || icon == null) return;
      vehicleIcon = icon;
      notifyListeners();
    } catch (e) {
      debugPrint('No se pudo dibujar el ícono del vehículo: $e');
    }
  }

  TripService get _trips => _tripsOverride ?? locator<TripService>();
  final RouteBatchRepository? _batchesOverride;
  RouteBatchRepository get _batches =>
      _batchesOverride ?? locator<RouteBatchRepository>();

  // --- Recorrido (CU-107, M4) ----------------------------------------------

  /// El recorrido aceptado al que pertenece este pedido; null si es un pedido
  /// suelto o no se pudo leer.
  RouteBatch? routeBatch;

  /// Paradas del recorrido en orden de entrega.
  List<RouteBatchStop> get batchStops => routeBatch?.stops ?? const [];

  /// `Recorrido: parada 2 de 4`; null fuera de un recorrido.
  String? get batchText {
    final n = routeBatch?.stopNumberOf(orderId);
    if (n == null) return null;
    return 'Recorrido: parada $n de ${batchStops.length}';
  }

  /// Busca entre mis recorridos (`GET /driver/route-batches`) el asignado que
  /// tiene este pedido. Es de apoyo: si falla, la entrega sigue igual.
  Future<void> _loadRouteBatch() async {
    try {
      final mine = await _batches.mine();
      if (_disposed) return;
      routeBatch = mine
          .where((b) => b.isAssigned && b.stopNumberOf(orderId) != null)
          .firstOrNull;
      notifyListeners();
    } catch (e) {
      debugPrint('No se pudo leer el recorrido del pedido $orderId: $e');
    }
  }

  final _navigationService = locator<NavigationService>();
  final _dialogService = locator<DialogService>();
  final _driverSocketService = locator<DriverSocketService>();
  LocationService get _location => locator<LocationService>();

  Timer? _pollTimer;

  /// Reintento de abrir el cobro cuando la navegación no lo dejó arriba.
  Timer? _paymentRetry;
  bool _pollInFlight = false;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Map<String, dynamic>>? _cancelSub;
  StreamSubscription<Map<String, dynamic>>? _addressSub;
  bool _disposed = false;
  Timer? _noPositionTimer;
  int _noPositionRetries = 0;
  static const int _maxNoPositionRetries = 5;
  bool _closing = false;

  /// El back dijo que el pedido ya no es del chofer (410, o 404/403 de un
  /// pedido que tenía en curso).
  bool _gone = false;

  /// La pantalla del QR está arriba: ella maneja la cancelación y el cobro.
  bool _qrOpen = false;

  TripOrder? order;
  RatingSummary? customerRating;

  /// Fallo al cargar el pedido (la pantalla ofrece reintentar).
  String? loadError;

  /// Error de la última acción (salir, avisar llegada, llamar, navegar).
  String? errorMessage;

  /// Aviso no bloqueante (ej.: se abrió la web en vez de la app de mapas).
  String? notice;

  bool _updating = false;
  bool get isUpdatingStatus => _updating;

  bool _releasing = false;

  /// Liberación del pedido en curso (`PATCH /orders/:id/cancel`).
  bool get isReleasing => _releasing;

  /// El chofer puede liberar el pedido: lo tiene aceptado o en camino.
  bool get canRelease => (isAccepted || isOnTheWay) && !_closing;

  /// El chofer ya avisó al cliente que llegó (`PATCH arrived`). El back no
  /// cambia el estado, sólo notifica.
  bool arrivedNotified = false;

  LatLng? driverPosition;

  /// Rumbo del vehículo en grados (0 = norte).
  double vehicleHeading = 0;
  LatLng? _previousPosition;

  /// Ya hubo un rumbo propio (GPS o movimiento); antes, el vehículo mira hacia
  /// donde va la ruta.
  bool _headingKnown = false;

  /// Ícono del vehículo en el mapa (null hasta que se dibuja).
  BitmapDescriptor? vehicleIcon;

  RouteTracker? _tracker;

  /// La cámara sigue al vehículo; se apaga cuando el chofer toca el mapa y se
  /// vuelve a prender con el botón de recentrar.
  bool followCamera = true;

  DriverOrderStatus? get status => order?.status;
  bool get isAccepted => status == DriverOrderStatus.accepted;
  bool get isOnTheWay => status == DriverOrderStatus.onTheWay;
  bool get isDelivered => status == DriverOrderStatus.delivered;

  /// Rótulo de la tarjeta superior según el estado del pedido.
  String get statusText => switch (status) {
        DriverOrderStatus.onTheWay =>
          etaText == null ? 'En camino' : 'En camino - $etaText',
        DriverOrderStatus.cancelled => 'Cancelado',
        DriverOrderStatus.pending ||
        DriverOrderStatus.reserved =>
          'Pedido liberado',
        DriverOrderStatus.delivered => 'Entregado',
        _ => 'Pedido aceptado',
      };

  /// Cancelado, o liberado/reasignado: el chofer ya no tiene el pedido.
  bool get isLost =>
      status == DriverOrderStatus.cancelled ||
      status == DriverOrderStatus.pending ||
      status == DriverOrderStatus.reserved;

  LatLng? get destination => (order?.hasCoordinates ?? false)
      ? LatLng(order!.lat!, order!.lng!)
      : null;

  /// Ruta vigente (por calles o, sin clave, la línea recta de respaldo).
  SplgRoute? get route => _tracker?.route;

  /// Metros que faltan hasta la dirección, siguiendo la ruta.
  double? get distanceMeters {
    final p = driverPosition;
    if (p == null || destination == null) return null;
    return _tracker?.remainingMeters(p) ?? Geo.distanceMeters(p, destination!);
  }

  /// "1,2 km" / "350 m".
  String? get distanceText {
    final m = distanceMeters;
    if (m == null) return null;
    return m >= 1000
        ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
        : '${m.round()} m';
  }

  /// "8 min" (nunca menos de "1 min"); null si la ruta no trae estimación.
  String? get etaText {
    final p = driverPosition;
    final s = p == null ? null : _tracker?.remainingSeconds(p);
    if (s == null) return null;
    final min = (s / 60).ceil();
    return min < 1 ? '1 min' : '$min min';
  }

  /// "8 min - 1,2 km", o sólo la distancia si no hay estimación.
  String? get tripSummary {
    final d = distanceText;
    if (d == null) return null;
    final e = etaText;
    return e == null ? d : '$e - $d';
  }

  /// Marcadores fijos (la dirección); el vehículo lo arma `SplgAnimatedVehicle`.
  Set<Marker> get markers {
    if (!identical(_markersFor, order)) {
      _markersFor = order;
      _markers = {
        if (destination != null)
          Marker(
            markerId: const MarkerId('destination'),
            position: destination!,
            infoWindow: InfoWindow(title: order?.address ?? 'Entrega'),
          ),
      };
    }
    return _markers;
  }

  Set<Marker> _markers = const {};
  TripOrder? _markersFor;

  /// Ruta que falta recorrer, en color de marca; punteada si es de respaldo.
  Set<Polyline> get polylines => _polylines;
  Set<Polyline> _polylines = const {};

  /// Se arma sólo cuando cambia la posición o la ruta, no en cada cuadro de la
  /// animación del vehículo.
  void _rebuildPolylines() {
    final p = driverPosition, t = _tracker;
    if (p == null || t == null || destination == null) {
      _polylines = const {};
      return;
    }
    _polylines = {
      splgRoutePolyline(t.remainingPoints(p),
          color: AppColors.llama600, dashed: t.route?.isFallback ?? true),
    };
  }

  Completer<GoogleMapController> mapController = Completer();

  Future<void> onMapCreated(GoogleMapController c) async {
    if (!mapController.isCompleted) mapController.complete(c);
    await _moveCamera();
  }

  /// El chofer tocó el mapa: deja de seguirlo.
  void userMovedMap() {
    if (!followCamera) return;
    followCamera = false;
    notifyListeners();
  }

  /// Botón de recentrar: vuelve a seguir al vehículo.
  Future<void> recenter() async {
    followCamera = true;
    notifyListeners();
    await _moveCamera(force: true);
  }

  DateTime _lastCameraMove = DateTime.fromMillisecondsSinceEpoch(0);

  /// En camino la cámara sigue al vehículo (rumbo y leve inclinación, como
  /// la referencia de diseño); antes de salir encuadra el chofer, la ruta y la dirección.
  Future<void> _moveCamera({bool force = false}) async {
    final d = destination;
    if (d == null || !mapController.isCompleted) return;
    if (!force && !followCamera) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastCameraMove) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastCameraMove = now;
    final p = driverPosition;
    try {
      final c = await mapController.future;
      if (isOnTheWay && p != null) {
        await c.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
          target: p,
          zoom: 17,
          bearing: vehicleHeading,
          tilt: 45,
        )));
      } else if (p == null) {
        await c.animateCamera(CameraUpdate.newLatLngZoom(d, 15));
      } else {
        final pts = [p, d, ...?_tracker?.remainingPoints(p)];
        double minLat = pts.first.latitude, maxLat = minLat;
        double minLng = pts.first.longitude, maxLng = minLng;
        for (final q in pts) {
          minLat = math.min(minLat, q.latitude);
          maxLat = math.max(maxLat, q.latitude);
          minLng = math.min(minLng, q.longitude);
          maxLng = math.max(maxLng, q.longitude);
        }
        await c.animateCamera(CameraUpdate.newLatLngBounds(
            LatLngBounds(
                southwest: LatLng(minLat, minLng),
                northeast: LatLng(maxLat, maxLng)),
            90));
      }
    } catch (e) {
      debugPrint('No se pudo mover la cámara: $e');
    }
  }

  /// Compatibilidad con el botón de encuadrar: recentra.
  Future<void> fitRoute() => recenter();

  void _onPosition(double lat, double lng, {double? heading, double? speed}) {
    final pos = LatLng(lat, lng);
    _headingKnown =
        (heading != null && heading >= 0 && speed != null && speed >= 1) ||
            (_previousPosition != null &&
                Geo.distanceMeters(_previousPosition!, pos) >= 3) ||
            _headingKnown;
    vehicleHeading = resolveHeading(
      gpsHeading: heading,
      speedMps: speed,
      previous: _previousPosition,
      current: pos,
      fallback: vehicleHeading,
    );
    if (_previousPosition == null ||
        Geo.distanceMeters(_previousPosition!, pos) >= 3) {
      _previousPosition = pos;
    }
    driverPosition = pos;
    _reportPosition(pos);
    _rebuildPolylines();
    notifyListeners();
    _updateRoute(pos);
    _moveCamera();
  }

  /// Cada posición llega al back por `driver:update-location` también desde la
  /// pantalla del pedido: el Home ya no está escuchando y sin posición el back
  /// no puede trazar la ruta (409). Se reenvía con cada lectura del pedido para
  /// cubrir un socket que conectó después de la primera posición.
  void _reportPosition(LatLng pos) {
    final userId = locator<DriverAuthService>().userId;
    if (userId == null || !_driverSocketService.isConnected) return;
    _driverSocketService.sendLocation(userId, pos.latitude, pos.longitude);
  }

  /// Con 409 el back todavía no tiene la posición: se vuelve a pedir enseguida
  /// con un tracker nuevo, sin esperar los 90 s de la política de recálculo.
  void _retryRouteSoon() {
    final svc = _routes;
    if (svc is! BackendRouteService || !svc.missingPosition) {
      _noPositionRetries = 0;
      return;
    }
    if (_noPositionRetries >= _maxNoPositionRetries ||
        _noPositionTimer != null) {
      return;
    }
    _noPositionRetries++;
    _noPositionTimer = Timer(noPositionRetry, () {
      _noPositionTimer = null;
      final p = driverPosition;
      if (_disposed || p == null) return;
      _reportPosition(p);
      _tracker = null;
      _updateRoute(p);
    });
  }

  Future<void> _updateRoute(LatLng pos) async {
    final d = destination;
    if (d == null || _disposed) return;
    final tracker = _tracker ??= RouteTracker(destination: d, service: _routes);
    try {
      final changed = await tracker.update(pos);
      if (_disposed) return;
      if (changed) _retryRouteSoon();
      if (changed) {
        final r = tracker.route;
        // Sin rumbo propio (quieto), el vehículo mira hacia donde va la ruta.
        if (r != null && r.points.length > 1 && !_headingKnown) {
          vehicleHeading = Geo.bearing(r.points[0], r.points[1]);
        }
        _rebuildPolylines();
        notifyListeners();
        _moveCamera();
      }
    } catch (e) {
      debugPrint('No se pudo actualizar la ruta: $e');
    }
  }

  Future<void> initialize() async {
    final cur = _location.currentPosition;
    if (cur != null) {
      _onPosition(cur.latitude, cur.longitude,
          heading: cur.heading, speed: cur.speed);
    }
    _positionSub = _location.positionStream.listen((p) => _onPosition(
        p.latitude, p.longitude,
        heading: p.heading, speed: p.speed));
    _loadVehicleIcon();
    unawaited(_loadRouteBatch());
    pickups.addListener(notifyListeners);
    _cancelSub = _driverSocketService.orderCancelled.listen((payload) {
      // Con el QR arriba, ese es el único que maneja la cancelación.
      if (_qrOpen) return;
      if (payload['orderId']?.toString() == orderId) {
        _refresh(silent: true);
      }
    });
    _addressSub = _driverSocketService.orderAddressChanged.listen((payload) {
      if (payload['orderId']?.toString() == orderId) {
        unawaited(_onAddressChanged());
      }
    });
    setBusy(true);
    await _refresh();
    setBusy(false);
    _startPolling();
  }

  /// El cliente cambió adónde se entrega: se relee el pedido, la ruta va al
  /// destino nuevo y se avisa en la tarjeta del viaje.
  Future<void> _onAddressChanged() async {
    await _refresh(silent: true);
    if (_disposed) return;
    _tracker = null;
    notice = 'El cliente cambió la dirección de entrega: la ruta se actualizó.';
    final p = driverPosition;
    if (p != null) unawaited(_updateRoute(p));
    _moveCamera(force: true);
    notifyListeners();
  }

  Future<void> retry() async {
    setBusy(true);
    await _refresh();
    setBusy(false);
    _startPolling();
  }

  @override
  void dispose() {
    _disposed = true;
    pickups.removeListener(notifyListeners);
    pickups.dispose();
    _stopPolling();
    _paymentRetry?.cancel();
    _noPositionTimer?.cancel();
    _positionSub?.cancel();
    _cancelSub?.cancel();
    _addressSub?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _stopPolling();
    if (_closing || isDelivered || isLost) return;
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      // Con la red lenta una lectura puede tardar más que el intervalo: no se
      // apilan consultas.
      if (_pollInFlight) return;
      _pollInFlight = true;
      try {
        await _refresh(silent: true);
      } finally {
        _pollInFlight = false;
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_closing) return;
    try {
      final fresh = await _trips.order(orderId);
      if (_disposed) return;
      final firstLoad = order == null;
      order = fresh;
      loadError = null;
      _rebuildEmpties();
      if (firstLoad) {
        final cid = fresh.customerId;
        if (cid != null) {
          _trips.customerRating(cid).then((r) {
            if (_disposed) return;
            customerRating = r;
            notifyListeners();
          });
        }
        final p = driverPosition;
        if (p != null) {
          _reportPosition(p);
          _updateRoute(p);
        }
        _moveCamera(force: true);
      }
      // El cliente puede aceptar el retiro con el viaje en curso: se relee cada
      // tanto, no en cada lectura.
      unawaited(pickups.load(every: kPickupsRefresh));
    } catch (e) {
      debugPrint('Error leyendo el pedido $orderId: $e');
      if (isOrderGone(e, known: order != null)) {
        _gone = true;
      } else if (!silent && order == null) {
        loadError = _text(e);
      }
    }
    if (_disposed) return;
    final last = driverPosition;
    if (last != null) _reportPosition(last);
    notifyListeners();
    if (_gone || (order != null && isLost)) {
      await _onLost();
    } else if (isDelivered) {
      await _onDelivered();
    }
  }

  /// El pedido ya no es del chofer: se corta el reparto, se avisa y se vuelve
  /// al Inicio (que sigue en línea).
  Future<void> _onLost() async {
    if (_closing) return;
    _closing = true;
    _stopPolling();
    _driverSocketService.stopTracking();
    final cancelled = !_gone && status == DriverOrderStatus.cancelled;
    await _dialogService.showDialog(
      title: cancelled ? 'Pedido cancelado' : 'Pedido liberado',
      description: cancelled
          ? 'El pedido fue cancelado. Seguís en línea para recibir otros.'
          : 'El pedido ya no está asignado a vos. Seguís en línea para recibir otros.',
    );
    _trips.endFlow();
    _goHome();
  }

  /// Lo entregó el cliente (escaneó el QR) mientras el chofer estaba acá:
  /// sigue el cobro.
  Future<void> _onDelivered() async {
    if (_closing) return;
    _closing = true;
    _stopPolling();
    _driverSocketService.stopTracking();
    if (openPaymentView(_navigationService, orderId)) {
      _trips.paymentOpenedFor = orderId;
      return;
    }
    // No se abrió el cobro: se reintenta en la próxima vuelta del sondeo (con
    // el pedido entregado el sondeo normal no corre).
    debugPrint('El cobro de $orderId no quedó abierto: se reintenta');
    _closing = false;
    if (_disposed) return;
    _paymentRetry?.cancel();
    _paymentRetry = Timer(pollInterval, () {
      _paymentRetry = null;
      if (!_disposed) unawaited(_refresh(silent: true));
    });
  }

  String _text(Object e) => actionErrorText(e,
      fallback: 'No pudimos completar la acción. Probá de nuevo.');

  /// "Salir hacia el cliente": `PATCH status on_the_way`.
  Future<void> markOnTheWay() async {
    if (_updating || _releasing || !isAccepted) return;
    _updating = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _trips.setStatus(orderId, 'on_the_way');
      await _refresh();
    } catch (e) {
      errorMessage = _text(e);
    }
    _updating = false;
    if (!_disposed) notifyListeners();
  }

  /// El chofer libera el pedido que no puede entregar (`PATCH
  /// /orders/:id/cancel`): el back lo devuelve a pendiente para otro chofer.
  /// La vista pide la confirmación antes. Con éxito se corta el reparto y se
  /// vuelve al Inicio, que sigue en línea. Si el back lo rechaza se muestra el
  /// motivo y se relee el pedido (pudo haberse entregado, cancelado o
  /// reasignado mientras tanto). Devuelve `true` si quedó liberado.
  Future<bool> releaseOrder() async {
    if (_updating || _releasing || !canRelease) return false;
    _releasing = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _trips.release(orderId);
    } catch (e) {
      debugPrint('Error liberando el pedido $orderId: $e');
      _releasing = false;
      if (_disposed) return false;
      errorMessage = _text(e);
      notifyListeners();
      await _refresh(silent: true);
      return false;
    }
    _releasing = false;
    _closing = true;
    _stopPolling();
    _driverSocketService.stopTracking();
    _trips.endFlow();
    _goHome();
    return true;
  }

  /// "Llegué / Entregar": avisa al cliente (`PATCH /v2/orders/:id/arrived` con
  /// la posición actual) y abre la entrega con QR. Sin ubicación no se llama al
  /// back; si el back dice que el chofer todavía está lejos (409
  /// `ARRIVAL_TOO_FAR`) se muestra su mensaje y el chofer puede reintentar. Si
  /// el aviso falla se dice y no se avanza.
  Future<void> arriveAndDeliver() async {
    if (_updating || _releasing || !isOnTheWay) return;
    _updating = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (!arrivedNotified) {
        final read = await _arrivalPosition();
        if (_disposed) return;
        final here = read.position;
        if (here == null) {
          await _failNoLocation(read.block ?? LocationBlock.unreadable);
          return;
        }
        await _trips.arrived(orderId,
            latitude: here.latitude, longitude: here.longitude);
        arrivedNotified = true;
      }
      await _declareEmpties();
    } catch (e) {
      debugPrint('Error antes de abrir el QR del pedido $orderId: $e');
      if (e is DioException && isArrivalTooFar(e)) {
        final text = arrivalTooFarText(e);
        _failArrival(text);
        if (!_disposed) {
          await _dialogService.showDialog(
            title: 'Todavía no llegaste',
            description: text,
            buttonTitle: 'Entendido',
          );
        }
        return;
      }
      _failArrival(_text(e));
      return;
    }
    _updating = false;
    if (_disposed) return;
    notifyListeners();
    await openDeliveryQr();
  }

  void _failArrival(String text) {
    errorMessage = text;
    _updating = false;
    if (!_disposed) notifyListeners();
  }

  /// Sin ubicación no se avisa. Con el permiso bloqueado para siempre, además
  /// se ofrece abrir los ajustes de la app.
  Future<void> _failNoLocation(LocationBlock block) async {
    final text = noLocationText(block);
    _failArrival(text);
    if (block != LocationBlock.permissionPermanentlyDenied || _disposed) return;
    final response = await _dialogService.showDialog(
      title: 'Ubicación bloqueada',
      description: text,
      buttonTitle: 'Abrir Ajustes',
      cancelTitle: 'Ahora no',
    );
    if (response?.confirmed == true) await _location.openDeviceSettings();
  }

  /// Con permiso y GPS prendido: la última posición del stream si tiene entre
  /// 0 y [arrivalPositionMaxAge] (una con hora futura no cuenta como fresca);
  /// si no, una lectura nueva del GPS. Sin permiso o con el GPS apagado no se
  /// usa ni la posición guardada. Si el permiso se puede volver a pedir (lo
  /// revocó durante el reparto), se pide con la misma explicación que al
  /// conectarse; si lo da, se lee el GPS de nuevo.
  Future<PositionRead> _arrivalPosition() async {
    final block = await _location.locationBlock();
    if (block == LocationBlock.permissionDenied) {
      await _location.requestLocationPermission();
      if (_disposed) {
        return const PositionRead.blocked(LocationBlock.permissionDenied);
      }
      final after = await _location.locationBlock();
      if (after != null) return PositionRead.blocked(after);
      return _location.readFreshPosition(timeout: arrivalPositionTimeout);
    }
    if (block != null) return PositionRead.blocked(block);
    final last = _location.currentPosition;
    if (last != null) {
      final age = _clock().difference(last.timestamp);
      if (!age.isNegative && age <= arrivalPositionMaxAge) {
        return PositionRead.ok(last);
      }
    }
    return _location.readFreshPosition(timeout: arrivalPositionTimeout);
  }

  // --- Vacías recibidas (F35 E4) ------------------------------------------

  /// Vacías por tipo de garrafa, en el orden del pedido. Vacía si el pedido no
  /// trae el tipo de cada renglón.
  List<EmptiesRow> emptiesRows = const [];

  /// Lo que el chofer movió en el selector, por tipo; se conserva entre
  /// lecturas del pedido hasta que el back lo registra.
  final Map<String, int> _emptiesDraft = {};

  /// La sección «Vacías» se muestra en camino, antes del QR.
  bool get showEmpties => isOnTheWay && emptiesRows.isNotEmpty;

  /// El chofer cambió alguna cantidad respecto de lo registrado en el back.
  bool get emptiesChanged => emptiesRows.any((r) => r.changed);

  /// Un renglón por tipo de garrafa (el back arma un renglón por tipo). Las
  /// esperadas y las declaradas las manda el back: la app no hace cuentas.
  void _rebuildEmpties() {
    final lines = order?.lines ?? const <OrderLine>[];
    emptiesRows = [
      for (final l in lines)
        if (l.gasCylinderId case final id?)
          () {
            final max = l.emptiesExpected;
            final declared = _clampEmpties(l.emptiesReceived ?? max, max);
            return EmptiesRow(
              gasCylinderId: id,
              label: l.label,
              expected: max,
              purchased: l.containersCharged,
              declared: declared,
              value: _clampEmpties(_emptiesDraft[id] ?? declared, max),
            );
          }(),
    ];
  }

  static int _clampEmpties(int v, int max) => v < 0 ? 0 : (v > max ? max : v);

  void _setEmpties(String gasCylinderId, int delta) {
    final i = emptiesRows.indexWhere((r) => r.gasCylinderId == gasCylinderId);
    if (i < 0 || _updating) return;
    final r = emptiesRows[i];
    final next = r.value + delta;
    if (next < 0 || next > r.expected) return;
    _emptiesDraft[gasCylinderId] = next;
    _rebuildEmpties();
    notifyListeners();
  }

  /// «Te dio» +1 (hasta las esperadas).
  void addEmpty(String gasCylinderId) => _setEmpties(gasCylinderId, 1);

  /// «Te dio» −1 (hasta 0).
  void removeEmpty(String gasCylinderId) => _setEmpties(gasCylinderId, -1);

  /// Si el chofer cambió algo, `PATCH /v2/orders/:id/empties` con todos los
  /// tipos y el pedido que devuelve el back pasa a ser el vigente. Si no cambió
  /// nada no se llama. Lanza si el back lo rechaza.
  Future<void> _declareEmpties() async {
    if (!emptiesChanged) return;
    final fresh = await _trips.declareEmpties(
        orderId, {for (final r in emptiesRows) r.gasCylinderId: r.value});
    if (_disposed) return;
    order = fresh;
    _emptiesDraft.clear();
    _rebuildEmpties();
  }

  /// Abre la pantalla del QR. Mientras está abierta ella lleva el control del
  /// pedido; al volver se retoma el seguimiento.
  Future<void> openDeliveryQr() async {
    _stopPolling();
    _qrOpen = true;
    final flow = _trips.activeOrderId;
    await _navigationService.navigateToDeliveryQrView(orderId: orderId);
    _qrOpen = false;
    if (_disposed || _closing) return;
    // El QR cerró la entrega: o la terminó (cancelado o liberado: ya avisó y
    // volvió al Inicio) o abrió el cobro. Releer acá repetiría el aviso o
    // abriría el cobro otra vez.
    if ((flow != null && _trips.activeOrderId != flow) ||
        _trips.paymentOpenedFor == orderId) {
      _closing = true;
      return;
    }
    await _refresh(silent: true);
    _startPolling();
  }

  /// `tel:` con el teléfono del cliente.
  Future<void> callCustomer() async {
    final phone = order?.customerPhone;
    if (phone == null) {
      errorMessage = 'El cliente no tiene teléfono cargado.';
      notifyListeners();
      return;
    }
    if (!await NavigationLauncher.dial(phone)) {
      errorMessage = 'No pudimos abrir el teléfono.';
      notifyListeners();
    }
  }

  /// Abre [map] hacia la dirección; avisa si cayó a la web.
  Future<void> navigateWith(MapApp map) async {
    final d = destination;
    if (d == null) {
      errorMessage = 'No hay coordenadas de entrega para navegar.';
      notifyListeners();
      return;
    }
    final r = await NavigationLauncher.open(map, d.latitude, d.longitude);
    if (r == MapLaunch.web) {
      notice = NavigationLauncher.webNotice(map);
    } else if (r == MapLaunch.failed) {
      errorMessage = 'No pudimos abrir el mapa.';
    }
    notifyListeners();
  }

  void clearMessages() {
    errorMessage = null;
    notice = null;
  }

  // --- Extras: incidencias y envases --------------------------------------

  /// Reporte de incidencia en curso (`POST /incidents`).
  bool _reportingIncident = false;
  bool get isReportingIncident => _reportingIncident;

  /// Asignación de envases físicos al pedido (`POST /cylinders/assign`).
  bool _assigningCylinders = false;
  bool get isAssigningCylinders => _assigningCylinders;
  int _assignedCylinders = 0;
  int get assignedCylinders => _assignedCylinders;
  String? cylinderError;

  /// Reporta una incidencia de entrega (CU-024): `POST /incidents` con
  /// `{ orderId, type, description }`. `type` debe ser uno de los valores del
  /// enum del backend (`damaged` | `out_of_stock` | `no_show` | `other`).
  /// Devuelve `true` si el backend la registró.
  Future<bool> reportIncident({
    required String type,
    required String description,
  }) async {
    if (_reportingIncident) return false;

    _reportingIncident = true;
    errorMessage = null;
    notifyListeners();

    var ok = false;
    try {
      final response = await _trips.reportIncident(orderId, type, description);
      ok = response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Error reportando incidencia del pedido $orderId: $e');
      errorMessage = _text(e);
      if (isIdempotencyConflict(e)) await _refresh(silent: true);
    }

    _reportingIncident = false;
    notifyListeners();
    return ok;
  }

  /// Asigna envases físicos (por serial) a este pedido y los despacha
  /// (`POST /cylinders/assign` → filled→dispatched). Se usa cuando el chofer
  /// carga en el camión los envases que salen para este pedido. Al confirmarse
  /// la entrega, el backend los avanza solo a "con el cliente". Devuelve `true`
  /// si el backend los despachó. Los envases deben estar en estado "llena".
  Future<bool> assignCylinders(List<String> serials) async {
    if (_assigningCylinders || serials.isEmpty) return false;

    _assigningCylinders = true;
    cylinderError = null;
    notifyListeners();

    var ok = false;
    try {
      final response = await _trips.assignCylinders(orderId, serials);
      ok = response.statusCode == 200 || response.statusCode == 201;
      if (ok) {
        _assignedCylinders += serials.length;
      } else {
        final data = response.data;
        final msg = (data is Map && data['message'] != null)
            ? (data['message'] is List
                ? (data['message'] as List).join(', ')
                : data['message'].toString())
            : null;
        cylinderError = msg ??
            'No se pudieron despachar los envases (HTTP ${response.statusCode}).';
      }
    } catch (e) {
      debugPrint('Error asignando envases del pedido $orderId: $e');
      cylinderError = _text(e);
      if (isIdempotencyConflict(e)) await _refresh(silent: true);
    }

    _assigningCylinders = false;
    notifyListeners();
    return ok;
  }
}
