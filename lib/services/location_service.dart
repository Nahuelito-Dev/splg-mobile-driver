import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:geolocator/geolocator.dart';
import 'package:splg_lib/permissions/app_permission.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/app_permissions.dart';

class LocationService with ListenableServiceMixin {
  LocationService() {
    listenToReactiveValues([
      _locationPermission,
      _serviceDisabled,
      _currentPosition,
      _isTracking,
    ]);
  }

  // Stream controller para la posición del usuario
  final _positionStreamController = StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionStreamController.stream;

  // Variables reactivas
  final ReactiveValue<PermissionOutcome> _locationPermission =
      ReactiveValue<PermissionOutcome>(PermissionOutcome.denied);
  PermissionOutcome get locationPermission => _locationPermission.value;

  /// true si el permiso está pero el GPS del teléfono está apagado.
  final ReactiveValue<bool> _serviceDisabled = ReactiveValue<bool>(false);
  bool get serviceDisabled => _serviceDisabled.value;

  AppPermissions get _permissions => locator<AppPermissions>();

  final ReactiveValue<Position?> _currentPosition =
      ReactiveValue<Position?>(null);
  Position? get currentPosition => _currentPosition.value;

  final ReactiveValue<bool> _isTracking = ReactiveValue<bool>(false);
  bool get isTracking => _isTracking.value;

  StreamSubscription<Position>? _positionSubscription;

  /// Estado del permiso sin pedir nada ni mostrar avisos (se puede llamar las
  /// veces que haga falta: al reanudar la app, antes de empezar el tracking).
  Future<bool> checkLocationPermission() async {
    final outcome =
        await _permissions.ensure(AppPermission.location, interactive: false);
    return _applyOutcome(outcome);
  }

  /// Pide el permiso de ubicación (mientras la app está abierta) con la
  /// explicación previa. Es la única puerta que muestra avisos.
  Future<bool> requestLocationPermission() async {
    final outcome = await _permissions.ensure(AppPermission.location);
    return _applyOutcome(outcome);
  }

  Future<bool> _applyOutcome(PermissionOutcome outcome) async {
    _locationPermission.value = outcome;
    if (!outcome.isGranted) return false;

    // El permiso está, pero el GPS del teléfono puede estar apagado.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _serviceDisabled.value = true;
      return false;
    }
    _serviceDisabled.value = false;
    return true;
  }

  /// Obtiene la ubicación actual del usuario una sola vez
  Future<Position?> getCurrentLocation() async {
    try {
      if (!await checkLocationPermission()) {
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
      if (!await checkLocationPermission()) {
        debugPrint('No se puede iniciar el tracking sin permisos');
        return;
      }

      if (_isTracking.value) {
        debugPrint('El tracking ya está activo');
        return;
      }

      _isTracking.value = true;

      // Configuración del stream de posición. En iOS sigue entregando
      // posiciones con la app minimizada (UIBackgroundModes: location) y lo
      // avisa con la barra azul del sistema; en Android lo mantiene vivo el
      // servicio en primer plano (flutter_foreground_task).
      final LocationSettings locationSettings =
          defaultTargetPlatform == TargetPlatform.iOS
              ? AppleSettings(
                  accuracy: LocationAccuracy.high,
                  activityType: ActivityType.automotiveNavigation,
                  distanceFilter: 10,
                  pauseLocationUpdatesAutomatically: false,
                  showBackgroundLocationIndicator: true,
                  allowBackgroundLocationUpdates: true,
                )
              : AndroidSettings(
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
    await _permissions.openSettings();
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
