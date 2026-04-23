import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:driver_mobile/app/app.locator.dart';
import 'package:driver_mobile/app/app.router.dart';
import 'package:driver_mobile/services/order_service.dart';
import 'package:driver_mobile/services/location_service.dart';

class HomeViewModel extends StreamViewModel<Position> {
  final _orderService = locator<OrderService>();
  final _locationService = locator<LocationService>();
  final _navigationService = locator<NavigationService>();

  Completer<GoogleMapController> mapController = Completer();

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

  /// Conecta al chofer para recibir órdenes
  Future<void> connect() async {
    // TODO: Implementar lógica de conexión
    debugPrint('Conectando chofer...');
  }

  @override
  List<ListenableServiceMixin> get listenableServices => [
        _orderService,
        _locationService,
      ];
}
