import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Callback de arranque del foreground service. Corre en un ISOLATE aparte y
/// solo setea un TaskHandler mínimo: el socket y el GPS viven en el isolate
/// PRINCIPAL; el único objetivo del service es que Android/iOS no maten el
/// proceso mientras el chofer está en línea o repartiendo, así el socket y el
/// stream de ubicación siguen vivos en background.
@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

/// Encapsula el foreground service (mantener vivo el proceso del chofer).
class DriverForegroundService {
  bool _initialized = false;

  void _init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'splg_driver_online',
        channelName: 'Jeny Gas — Repartidor',
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

  /// Pide el permiso de notificaciones (Android 13+). Best-effort.
  Future<void> requestPermissions() async {
    try {
      final status = await FlutterForegroundTask.checkNotificationPermission();
      if (status != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (e) {
      debugPrint('[ForegroundService] permiso notif: $e');
    }
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
        callback: startForegroundCallback,
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
