import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:uuid/uuid.dart';

import 'package:driver_mobile/app/app.dialogs.dart';
import 'package:driver_mobile/app/app.locator.dart';
import 'package:driver_mobile/app/app.router.dart';
import 'package:driver_mobile/core/network/api_client.dart';
import 'package:driver_mobile/services/driver_auth_service.dart';
import 'package:driver_mobile/services/driver_socket_service.dart';
import 'package:driver_mobile/services/foreground_service.dart';
import 'package:driver_mobile/services/location_service.dart';

class HomeViewModel extends StreamViewModel<Position> {
  final _locationService = locator<LocationService>();
  final _navigationService = locator<NavigationService>();
  final _driverSocketService = locator<DriverSocketService>();
  final _dialogService = locator<DialogService>();
  final _foregroundService = locator<DriverForegroundService>();
  final _apiClient = ApiClient();
  final _uuid = const Uuid();

  // Lazy a propósito (no como los demás `locator<T>()` de arriba): resolver
  // DriverAuthService dispara `FirebaseAuth.instance` en su constructor, y
  // este ViewModel se instancia cada vez que se construye HomeView (incluso
  // en tests/goldens que no inicializan Firebase). Como getter, solo se
  // resuelve cuando efectivamente se usa (connect/acceptOrder/onData).
  DriverAuthService get _driverAuthService => locator<DriverAuthService>();

  Completer<GoogleMapController> mapController = Completer();

  StreamSubscription<Map<String, dynamic>>? _incomingOrdersSubscription;

  /// true una vez que el socket de choferes está conectado y el chofer quedó
  /// unido a su sala (`driver:join` emitido).
  bool get isConnected => _driverSocketService.isConnected;

  /// Nombre del chofer logueado (para el drawer). Fallback genérico si aún no
  /// se resolvió el perfil.
  String get driverName => _driverAuthService.fullName ?? 'Chofer';

  // Posición inicial del mapa (Buenos Aires, Argentina como ejemplo)
  static const CameraPosition initialPosition = CameraPosition(
    target: LatLng(-34.6037, -58.3816),
    zoom: 14.0,
  );

  Set<Marker> markers = {};
  LatLng? currentLocation;
  bool hasLocationPermission = false;
  String? permissionMessage;

  @override
  Stream<Position> get stream => _locationService.positionStream;

  @override
  void onData(Position? position) {
    if (position != null) {
      _updateUserLocation(position);

      // Si el chofer ya está conectado, cada nueva posición del tracking
      // también se reporta al GEO del backend (además de la que se manda
      // una sola vez al conectar), para que el dispatch siempre lo ubique.
      final userId = _driverAuthService.userId;
      if (isConnected && userId != null) {
        _driverSocketService.sendLocation(
          userId,
          position.latitude,
          position.longitude,
        );
      }
    }
  }

  // @override
  // void onError(error) {
  //   debugPrint('Error en el stream de ubicación: $error');
  //   permissionMessage = 'Error al obtener la ubicación';
  //   notifyListeners();
  // }

  /// Inicializa el ViewModel y verifica permisos
  Future<void> initialize() async {
    await _checkLocationPermission();
    if (hasLocationPermission) {
      await _locationService.startTracking();
    }
  }

  @override
  void dispose() {
    _incomingOrdersSubscription?.cancel();
    _locationService.stopTracking();
    mapController.future.then((controller) => controller.dispose());
    super.dispose();
  }

  Future<void> onMapCreated(GoogleMapController controller) async {
    if (!mapController.isCompleted) {
      mapController.complete(controller);
    }
  }

  /// Verifica el estado de los permisos de ubicación
  Future<void> _checkLocationPermission() async {
    hasLocationPermission =
        await _locationService.checkAndRequestLocationPermission();

    if (!hasLocationPermission) {
      PermissionStatus status = _locationService.locationPermissionStatus;

      if (status.isPermanentlyDenied) {
        permissionMessage =
            'Los permisos de ubicación están denegados permanentemente.\n'
            'Por favor, habilítalos en la configuración de la aplicación.';
      } else if (status.isDenied) {
        permissionMessage =
            'Se requieren permisos de ubicación para mostrar tu posición en el mapa.';
      } else {
        permissionMessage = 'El servicio de ubicación está deshabilitado.';
      }
    } else {
      permissionMessage = null;
    }

    notifyListeners();
  }

  /// Actualiza la ubicación del usuario en el mapa
  void _updateUserLocation(Position position) {
    currentLocation = LatLng(position.latitude, position.longitude);

    // Actualizar o agregar el marcador del usuario
    markers.removeWhere((m) => m.markerId.value == 'user_location');
    markers.add(
      Marker(
        markerId: const MarkerId('user_location'),
        position: currentLocation!,
        infoWindow: const InfoWindow(title: 'Mi ubicación'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
      ),
    );

    // Animar la cámara hacia la nueva ubicación (solo la primera vez)
    if (markers.length == 1) {
      _animateCameraToPosition(currentLocation!);
    }

    notifyListeners();
  }

  /// Anima la cámara hacia una posición específica
  Future<void> _animateCameraToPosition(LatLng position) async {
    try {
      final controller = await mapController.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: position,
            zoom: 16.0,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error al animar la cámara: $e');
    }
  }

  /// Solicita permisos de ubicación nuevamente
  Future<void> requestLocationPermission() async {
    await _checkLocationPermission();
    if (hasLocationPermission) {
      await _locationService.startTracking();
    }
  }

  /// Abre la configuración de la app para habilitar permisos
  Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Centra el mapa en la ubicación actual del usuario
  Future<void> centerOnUserLocation() async {
    if (currentLocation != null) {
      await _animateCameraToPosition(currentLocation!);
    }
  }

  /// Cierra sesión y navega a la pantalla de login
  Future<void> logout() async {
    // Detener el seguimiento de ubicación
    await _locationService.stopTracking();

    // Navegar a la pantalla de login y limpiar el stack de navegación
    await _navigationService.clearStackAndShow(Routes.loginView);
  }

  /// Conecta al chofer para recibir órdenes: abre el socket de choferes,
  /// registra su ubicación actual en el GEO y se suscribe a las ofertas de
  /// pedido que empuje el backend mientras esté conectado.
  Future<void> connect() async {
    if (isConnected) {
      debugPrint('connect() ignorado: el chofer ya está conectado');
      return;
    }

    final userId = _driverAuthService.userId;
    final token = await _driverAuthService.token;
    if (userId == null || token == null) {
      debugPrint('No se puede conectar: falta la sesión del chofer');
      return;
    }

    // Marca al chofer DISPONIBLE en el backend (CU-022). Sin esto el backend no
    // sabe formalmente que está en línea, y al desconectar hay que sacarlo del
    // radar (el endpoint hace el ZREM del GEO en el server).
    await _setAvailability(true);

    // Foreground service: mantiene vivo el proceso (socket + GPS) con la app en
    // background. Sin esto, al minimizar la app el chofer se cae del radar.
    await _foregroundService.requestPermissions();
    await _foregroundService.start(
      title: 'Estás en línea',
      text: 'Recibiendo pedidos cercanos',
    );

    _driverSocketService.connect(token, userId);

    // Registra la posición actual en el GEO apenas se conecta, sin esperar
    // al próximo tick del tracking de ubicación.
    final position =
        _locationService.currentPosition ?? await _locationService.getCurrentLocation();
    if (position != null) {
      _driverSocketService.sendLocation(
        userId,
        position.latitude,
        position.longitude,
      );
    }

    _subscribeToIncomingOrders();
    notifyListeners();
  }

  /// Desconecta al chofer: se marca NO DISPONIBLE (el backend lo saca del radar),
  /// deja de recibir ofertas y cierra el socket.
  Future<void> disconnect() async {
    await _setAvailability(false);
    await _foregroundService.stop();
    _incomingOrdersSubscription?.cancel();
    _incomingOrdersSubscription = null;
    _driverSocketService.disconnect();
    notifyListeners();
  }

  /// Setea la disponibilidad del chofer en el backend (CU-022).
  /// `PATCH /delivery/user/:userId/availability`. Best-effort: si falla, no
  /// bloquea el flujo del socket (se loguea).
  Future<void> _setAvailability(bool isAvailable) async {
    final token = await _driverAuthService.token;
    final userId = _driverAuthService.userId;
    if (token == null || userId == null) return;
    try {
      await _apiClient.patch(
        'delivery/user/$userId/availability',
        {'available': isAvailable},
        token,
      );
    } catch (e) {
      debugPrint('No se pudo setear disponibilidad ($isAvailable): $e');
    }
  }

  void _subscribeToIncomingOrders() {
    _incomingOrdersSubscription?.cancel();
    _incomingOrdersSubscription =
        _driverSocketService.incomingOrders.listen(_showOrderOfferDialog);
  }

  /// Muestra el dialog de "Nuevo pedido" por cada oferta que llega
  /// (`server:new-order-request` / `NEW_ORDER` | `NEW_ORDER_RETRY`).
  Future<void> _showOrderOfferDialog(Map<String, dynamic> offer) async {
    final orderId = offer['orderId']?.toString();
    if (orderId == null) {
      debugPrint('Oferta de pedido sin orderId, se ignora: $offer');
      return;
    }

    final response = await _dialogService.showCustomDialog(
      variant: DialogType.orderOffer,
      data: offer,
    );

    if (response?.confirmed == true) {
      await acceptOrder(orderId);
    } else {
      await rejectOrder(orderId);
    }
  }

  /// Rechaza una oferta (CU-016): `POST /orders/:orderId/reject`. El backend
  /// cierra la oferta y re-ofrece al siguiente chofer de inmediato. Best-effort.
  Future<void> rejectOrder(String orderId) async {
    final token = await _driverAuthService.token;
    if (token == null) return;
    try {
      await _apiClient.post(
        'orders/$orderId/reject',
        const {},
        token,
        {'Idempotency-Key': _uuid.v4()},
      );
      debugPrint('Oferta $orderId rechazada por el chofer');
    } catch (e) {
      debugPrint('Error rechazando la oferta $orderId: $e');
    }
  }

  /// Acepta un pedido ofertado: PATCH idempotente a `/orders/:orderId/status`
  /// con `status: accepted`. Si el backend confirma, arranca el broadcasting
  /// de posición GPS de la entrega.
  Future<void> acceptOrder(String orderId) async {
    final token = await _driverAuthService.token;
    final userId = _driverAuthService.userId;
    if (token == null || userId == null) {
      debugPrint('No se puede aceptar el pedido $orderId: falta la sesión');
      return;
    }

    try {
      final response = await _apiClient.patch(
        'orders/$orderId/status',
        {'status': 'accepted'},
        token,
        {'Idempotency-Key': _uuid.v4()},
      );

      if (response.statusCode == 200) {
        debugPrint('Pedido $orderId aceptado');
        _driverSocketService.startBroadcasting(orderId, userId, token);
        await _foregroundService.update(
          title: 'En reparto',
          text: 'Entrega en curso',
        );
        await _navigationService.navigateToDeliveryView(orderId: orderId);
      } else {
        debugPrint(
            'No se pudo aceptar el pedido $orderId: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error aceptando el pedido $orderId: $e');
    }
  }

  @override
  List<ListenableServiceMixin> get listenableServices => [
        _locationService,
        _driverSocketService,
      ];
}
