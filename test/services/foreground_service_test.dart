import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splg_driver/services/foreground_service.dart';

/// Plataforma falsa del plugin: registra qué se le pide sin tocar Android/iOS.
class _FakeForegroundPlatform extends FlutterForegroundTaskPlatform {
  bool running = false;
  bool failStart = false;
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
    if (failStart) throw StateError('no arrancó');
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
      await DriverForegroundService(hasLocationPermission: () async => true)
          .start(title: 'Estás en línea', text: 'Recibiendo pedidos cercanos');

      expect(platform.starts, 1);
      expect(platform.startCallback, isNull);
      expect(platform.title, 'Estás en línea');
      expect(platform.text, 'Recibiendo pedidos cercanos');
    });

    test('si ya está corriendo, sólo actualiza la notificación', () async {
      final service =
          DriverForegroundService(hasLocationPermission: () async => true);
      await service.start(title: 'Estás en línea', text: 'a');
      await service.start(title: 'En reparto', text: 'b');

      expect(platform.starts, 1);
      expect(platform.updates, 1);
      expect(platform.title, 'En reparto');
    });

    test(
        'sin permiso de ubicación NO arranca el servicio de tipo location '
        '(Android cerraría la app) y avisa que no quedó corriendo', () async {
      var asked = 0;
      final started = await DriverForegroundService(
        hasLocationPermission: () async {
          asked++;
          return false;
        },
      ).start(title: 'Estás en línea', text: 'x');

      expect(started, isFalse);
      expect(asked, 1);
      expect(platform.starts, 0);
      expect(platform.running, isFalse);
    });

    test('con permiso arranca y avisa que quedó corriendo', () async {
      final started =
          await DriverForegroundService(hasLocationPermission: () async => true)
              .start(title: 'Estás en línea', text: 'x');

      expect(started, isTrue);
      expect(platform.starts, 1);
    });

    test('si el plugin no lo pudo arrancar, devuelve false', () async {
      platform.failStart = true;
      final started =
          await DriverForegroundService(hasLocationPermission: () async => true)
              .start(title: 'Estás en línea', text: 'x');

      expect(started, isFalse);
    });

    test(
        'canStart exige siempre el permiso, aunque el servicio figure '
        'corriendo', () async {
      expect(
          await DriverForegroundService(hasLocationPermission: () async => true)
              .canStart(),
          isTrue);

      platform.running = true;
      final service =
          DriverForegroundService(hasLocationPermission: () async => false);
      expect(await service.isRunning, isTrue);
      expect(await service.canStart(), isFalse);
    });

    test('stop corta el servicio y no falla si no estaba corriendo', () async {
      final service =
          DriverForegroundService(hasLocationPermission: () async => true);
      await service.stop();
      expect(platform.stops, 0);

      await service.start(title: 't', text: 'x');
      await service.stop();
      expect(platform.stops, 1);
      expect(platform.running, isFalse);
    });
  });

  test(
      'Android: la app usa SplgDriverApplication, que al nacer el proceso deja '
      'el servicio como detenido (el plugin no lo revive solo sin permiso)',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application =
        RegExp(r'<application[^>]*>').firstMatch(manifest)!.group(0)!;
    expect(application, contains('android:name=".SplgDriverApplication"'));

    final guard = File(
      'android/app/src/main/kotlin/com/nahuelwagner/splg/driver/'
      'SplgDriverApplication.kt',
    ).readAsStringSync();
    expect(
      guard,
      contains(
        'ForegroundServiceStatus.setData(this, ForegroundServiceAction.API_STOP)',
      ),
    );
    expect(guard, contains('RestartReceiver.cancelRestartAlarm(this)'));
  });
}
