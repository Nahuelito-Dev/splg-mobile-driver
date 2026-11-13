import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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
class DriverForegroundService {
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

  /// Arranca (o actualiza) el service con la notificación persistente.
  Future<void> start({required String title, required String text}) async {
    _init();
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 2001,
        notificationTitle: title,
        notificationText: text,
      );
    } catch (e) {
      debugPrint('[ForegroundService] start: $e');
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
