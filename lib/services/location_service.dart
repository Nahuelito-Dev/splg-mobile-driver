import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:geolocator/geolocator.dart';
import 'package:splg_lib/permissions/app_permission.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/app_permissions.dart';

class LocationService with ListenableServiceMixin {
  /// Los parámetros existen para poder probar el servicio sin plugins reales;
  /// en la app van los de `geolocator`.
  LocationService({
    Stream<Position> Function(LocationSettings settings)? positionStreamFactory,
    Stream<ServiceStatus> Function()? serviceStatusStreamFactory,
    Future<bool> Function()? isServiceEnabled,
    Future<bool> Function()? openLocationSettings,
  })  : _positionStreamFactory = positionStreamFactory ??
            ((settings) =>
                Geolocator.getPositionStream(locationSettings: settings)),
        _serviceStatusStreamFactory =
            serviceStatusStreamFactory ?? Geolocator.getServiceStatusStream,
        _isServiceEnabled =
            isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
        _openLocationSettings =
            openLocationSettings ?? Geolocator.openLocationSettings {
    listenToReactiveValues([
      _locationPermission,
      _serviceDisabled,
      _currentPosition,
      _isTracking,
      _trackingFailed,
    ]);
  }

  final Stream<Position> Function(LocationSettings settings)
      _positionStreamFactory;
  final Stream<ServiceStatus> Function() _serviceStatusStreamFactory;
  final Future<bool> Function() _isServiceEnabled;
  final Future<bool> Function() _openLocationSettings;

  /// true si el stream de posición cayó (GPS apagado o permiso revocado) y
  /// todavía no se reanudó: el chofer no está llegando al despacho.
  final ReactiveValue<bool> _trackingFailed = ReactiveValue<bool>(false);
  bool get trackingFailed => _trackingFailed.value;

  /// Se pidió tracking y la ubicación no está llegando: stream caído, GPS
  /// apagado o permiso faltante.
  bool get locationUnavailable =>
      _trackingFailed.value ||
      (_wantTracking &&
          (_serviceDisabled.value ||
              _locationPermission.value != PermissionOutcome.granted));

  /// Mientras alguien pidió tracking (hasta [stopTracking]) se vigila el
  /// estado del servicio de ubicación para reanudar solo.
  bool _wantTracking = false;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

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

    // El GPS del teléfono puede estar apagado con o sin permiso.
    final serviceEnabled = await _isServiceEnabled();
    _serviceDisabled.value = !serviceEnabled;
    return outcome.isGranted && serviceEnabled;
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
    _wantTracking = true;
    _watchServiceStatus();
    try {
      if (!await checkLocationPermission()) {
        debugPrint('No se puede iniciar el tracking sin permisos');
        return;
      }

      // Un stopTracking pudo llegar mientras se esperaba el permiso.
      if (!_wantTracking) return;

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
      _positionSubscription = _positionStreamFactory(locationSettings).listen(
        (Position position) {
          _trackingFailed.value = false;
          _currentPosition.value = position;
          _positionStreamController.add(position);
          debugPrint(
              'Nueva posición: ${position.latitude}, ${position.longitude}');
        },
        onError: (Object error) {
          debugPrint('Error en el stream de posición: $error');
          _onTrackingError(error);
        },
      );

      debugPrint('Tracking de ubicación iniciado');
    } catch (e) {
      debugPrint('Error al iniciar el tracking: $e');
      _isTracking.value = false;
    }
  }

  /// El stream cayó: se corta, se marca la falla (para el aviso) y queda a la
  /// espera de que vuelva el servicio para reintentar.
  void _onTrackingError(Object error) {
    final subscription = _positionSubscription;
    _positionSubscription = null;
    subscription?.cancel();
    _isTracking.value = false;
    _trackingFailed.value = true;
    if (error is LocationServiceDisabledException) {
      _serviceDisabled.value = true;
    } else if (error is PermissionDeniedException) {
      _locationPermission.value = PermissionOutcome.denied;
    }
  }

  void _watchServiceStatus() {
    if (_serviceStatusSubscription != null) return;
    _serviceStatusSubscription = _serviceStatusStreamFactory().listen(
      (status) {
        if (!_wantTracking) return;
        if (status == ServiceStatus.disabled) {
          _serviceDisabled.value = true;
          if (_isTracking.value) {
            _onTrackingError(const LocationServiceDisabledException());
          } else {
            _trackingFailed.value = true;
          }
        } else {
          _serviceDisabled.value = false;
          if (_trackingFailed.value || !_isTracking.value) {
            unawaited(startTracking());
          }
        }
      },
      onError: (Object error) =>
          debugPrint('Error en el estado del servicio de ubicación: $error'),
    );
  }

  /// Abre el ajuste que corresponde a la falla: permiso → ajustes de la app;
  /// GPS apagado → ajustes de ubicación del sistema.
  Future<void> openLocationAlertSettings() async {
    if (!_serviceDisabled.value &&
        _locationPermission.value != PermissionOutcome.granted) {
      await openDeviceSettings();
    } else {
      await _openLocationSettings();
    }
  }

  /// Detiene el seguimiento de ubicación
  Future<void> stopTracking() async {
    _wantTracking = false;
    _trackingFailed.value = false;
    await _serviceStatusSubscription?.cancel();
    _serviceStatusSubscription = null;
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
    _serviceStatusSubscription?.cancel();
    _positionSubscription?.cancel();
    _positionStreamController.close();
  }
}
