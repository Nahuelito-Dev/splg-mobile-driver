import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splg_driver/services/foreground_service.dart';

/// Plataforma falsa del plugin: registra qué se le pide sin tocar Android/iOS.
class _FakeForegroundPlatform extends FlutterForegroundTaskPlatform {
  bool running = false;
  int starts = 0;
  int updates = 0;
  int stops = 0;
  Function? startCallback;
  String? title;
  String? text;

  @override
  Future<void> startService({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
    int? serviceId,
    required String notificationTitle,
    required String notificationText,
    NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons,
    String? notificationInitialRoute,
    Function? callback,
  }) async {
    starts++;
    startCallback = callback;
    title = notificationTitle;
    text = notificationText;
    running = true;
  }

  @override
  Future<void> updateService({
    ForegroundTaskOptions? foregroundTaskOptions,
    String? notificationTitle,
    String? notificationText,
    NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons,
    String? notificationInitialRoute,
    Function? callback,
  }) async {
    updates++;
    title = notificationTitle;
    text = notificationText;
  }

  @override
  Future<void> stopService() async {
    stops++;
    running = false;
  }

  @override
  Future<bool> get isRunningService async => running;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeForegroundPlatform platform;

  setUp(() {
    platform = _FakeForegroundPlatform();
    FlutterForegroundTaskPlatform.instance = platform;
    FlutterForegroundTask.resetStatic();
    FlutterForegroundTask.skipServiceResponseCheck = true;
  });

  group('DriverForegroundService', () {
    test(
        'arranca el servicio SIN callback: no se levanta un segundo motor de '
        'Dart en el hilo principal de Android (ANR al conectarse)', () async {
      await DriverForegroundService()
          .start(title: 'Estás en línea', text: 'Recibiendo pedidos cercanos');

      expect(platform.starts, 1);
      expect(platform.startCallback, isNull);
      expect(platform.title, 'Estás en línea');
      expect(platform.text, 'Recibiendo pedidos cercanos');
    });

    test('si ya está corriendo, sólo actualiza la notificación', () async {
      final service = DriverForegroundService();
      await service.start(title: 'Estás en línea', text: 'a');
      await service.start(title: 'En reparto', text: 'b');

      expect(platform.starts, 1);
      expect(platform.updates, 1);
      expect(platform.title, 'En reparto');
    });

    test('stop corta el servicio y no falla si no estaba corriendo', () async {
      final service = DriverForegroundService();
      await service.stop();
      expect(platform.stops, 0);

      await service.start(title: 't', text: 'x');
      await service.stop();
      expect(platform.stops, 1);
      expect(platform.running, isFalse);
    });
  });
}
