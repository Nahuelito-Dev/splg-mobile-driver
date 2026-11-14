import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:splg_lib/permissions/app_permission.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/app_permissions.dart';

/// Encapsula el foreground service: su único objetivo es que Android no mate el
/// proceso mientras el chofer está en línea o repartiendo, así el socket y el
/// stream de ubicación (que viven en el isolate principal) siguen vivos en
/// background. En iOS lo que lo sostiene es la ubicación en segundo plano
/// (`UIBackgroundModes: location`).
///
/// El servicio arranca SIN `callback` a propósito: con un callback, el plugin
/// crea en Android otro FlutterEngine y corre el bundle de Dart en un isolate
/// nuevo dentro de `onStartCommand`, en el hilo principal. Eso congela la app
/// varios segundos al tocar «Conectarse» y, con el equipo cargado, pasa los
/// 20 s y Android tira el ANR («executing service … ForegroundService»). Sin
/// callback el servicio igual muestra la notificación y mantiene el proceso.
///
/// El servicio se declara con `foregroundServiceType="location"`: Android 14+
/// tira `SecurityException` dentro de `onStartCommand` (nativo, fuera del
/// alcance de un try/catch de Dart) si se lo arranca sin el permiso de
/// ubicación, y la app se cae. Por eso [start] mira el permiso antes y, si
/// falta, no lo arranca. En el manifiesto va con `stopWithTask="true"` para
/// que Android no lo reinicie solo tras matar el proceso (sin el motor de
/// Dart de la app no sirve de nada y, sin permiso, es el mismo crash).
class DriverForegroundService {
  /// [hasLocationPermission] existe para los tests; en la app consulta el
  /// permiso de ubicación sin pedir nada.
  DriverForegroundService({Future<bool> Function()? hasLocationPermission})
      : _hasLocationPermission =
            hasLocationPermission ?? _locationPermissionGranted;

  final Future<bool> Function() _hasLocationPermission;

  static Future<bool> _locationPermissionGranted() async {
    final outcome =
        await locator<AppPermissions>().status(AppPermission.location);
    return outcome.isGranted;
  }

  bool _initialized = false;

  void _init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'splg_driver_online',
        channelName: 'SPLG Chofer',
        channelDescription:
            'Mantiene la conexión y el GPS activos mientras estás en línea.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  /// Si el servicio está corriendo ahora (estado real del plugin).
  Future<bool> get isRunning async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (e) {
      debugPrint('[ForegroundService] isRunning: $e');
      return false;
    }
  }

  /// Si el servicio puede estar corriendo: exige SIEMPRE el permiso de
  /// ubicación, aunque el plugin lo dé por corriendo (un servicio de tipo
  /// location sin permiso no tiene que seguir). No pide nada.
  Future<bool> canStart() async {
    try {
      return await _hasLocationPermission();
    } catch (e) {
      debugPrint('[ForegroundService] canStart: $e');
      return false;
    }
  }

  /// Arranca (o actualiza) el service con la notificación persistente.
  /// Devuelve si quedó corriendo: false si falta el permiso de ubicación (no
  /// se lo arranca) o si el plugin falló.
  Future<bool> start({required String title, required String text}) async {
    _init();
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return true;
      }
      if (!await _hasLocationPermission()) {
        debugPrint(
            '[ForegroundService] sin permiso de ubicación: no se arranca');
        return false;
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: 2001,
        notificationTitle: title,
        notificationText: text,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('[ForegroundService] start: ${result.error}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[ForegroundService] start: $e');
      return false;
    }
  }

  /// Actualiza el texto de la notificación (ej: pasar de "en línea" a "en reparto").
  Future<void> update({required String title, required String text}) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
      }
    } catch (e) {
      debugPrint('[ForegroundService] update: $e');
    }
  }

  Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('[ForegroundService] stop: $e');
    }
  }
}
