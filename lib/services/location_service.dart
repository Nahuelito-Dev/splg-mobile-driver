import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService with ListenableServiceMixin {
  LocationService() {
    listenToReactiveValues([
      _locationPermissionStatus,
      _currentPosition,
      _isTracking,
    ]);
  }

  // Stream controller para la posición del usuario
  final _positionStreamController = StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionStreamController.stream;

  // Variables reactivas
  final ReactiveValue<PermissionStatus> _locationPermissionStatus =
      ReactiveValue<PermissionStatus>(PermissionStatus.denied);
  PermissionStatus get locationPermissionStatus =>
      _locationPermissionStatus.value;

  final ReactiveValue<Position?> _currentPosition =
      ReactiveValue<Position?>(null);
  Position? get currentPosition => _currentPosition.value;

  final ReactiveValue<bool> _isTracking = ReactiveValue<bool>(false);
  bool get isTracking => _isTracking.value;

  StreamSubscription<Position>? _positionSubscription;

  /// Verifica y solicita permisos de ubicación
  Future<bool> checkAndRequestLocationPermission() async {
    try {
      // Verificar si el servicio de ubicación está habilitado
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Los servicios de ubicación están deshabilitados');
        _locationPermissionStatus.value = PermissionStatus.denied;
        return false;
      }

      // Verificar el estado del permiso
      PermissionStatus status = await Permission.location.status;
      _locationPermissionStatus.value = status;

      // Si está denegado, solicitar permiso
      if (status.isDenied) {
        status = await Permission.location.request();
        _locationPermissionStatus.value = status;
      }

      // Si está permanentemente denegado, indicar al usuario
      if (status.isPermanentlyDenied) {
        debugPrint('Permisos de ubicación denegados permanentemente');
        return false;
      }

      return status.isGranted;
    } catch (e) {
      debugPrint('Error al verificar permisos de ubicación: $e');
      return false;
    }
  }

  /// Obtiene la ubicación actual del usuario una sola vez
  Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await checkAndRequestLocationPermission();
      if (!hasPermission) {
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      _currentPosition.value = position;
      return position;
    } catch (e) {
      debugPrint('Error al obtener la ubicación actual: $e');
      return null;
    }
  }

  /// Inicia el seguimiento continuo de la ubicación del usuario
  Future<void> startTracking() async {
    try {
      bool hasPermission = await checkAndRequestLocationPermission();
      if (!hasPermission) {
        debugPrint('No se puede iniciar el tracking sin permisos');
        return;
      }

      if (_isTracking.value) {
        debugPrint('El tracking ya está activo');
        return;
      }

      _isTracking.value = true;

      // Configuración del stream de posición
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Actualizar cada 10 metros
      );

      // Suscribirse al stream de posición
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _currentPosition.value = position;
          _positionStreamController.add(position);
          debugPrint(
              'Nueva posición: ${position.latitude}, ${position.longitude}');
        },
        onError: (error) {
          debugPrint('Error en el stream de posición: $error');
        },
      );

      debugPrint('Tracking de ubicación iniciado');
    } catch (e) {
      debugPrint('Error al iniciar el tracking: $e');
      _isTracking.value = false;
    }
  }

  /// Detiene el seguimiento de ubicación
  Future<void> stopTracking() async {
    if (!_isTracking.value) {
      return;
    }

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking.value = false;
    debugPrint('Tracking de ubicación detenido');
  }

  /// Abre la configuración de la app para habilitar permisos.
  /// (Antes el método se llamaba `openAppSettings` y se invocaba a sí mismo →
  /// recursión infinita. Renombrado para llamar al de `permission_handler`.)
  Future<void> openDeviceSettings() async {
    await openAppSettings();
  }

  /// Calcula la distancia entre dos puntos en metros
  double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Limpia recursos al destruir el servicio
  void dispose() {
    _positionSubscription?.cancel();
    _positionStreamController.close();
  }
}
