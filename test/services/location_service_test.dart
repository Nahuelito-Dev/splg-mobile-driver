import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/app_permissions.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_lib/permissions/app_permission.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

Position _pos() => Position(
      latitude: -27.36,
      longitude: -55.89,
      timestamp: DateTime(2026, 11, 2),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );

void main() {
  group('LocationServiceTest -', () {
    late MockAppPermissions permissions;
    late List<StreamController<Position>> positionStreams;
    late StreamController<ServiceStatus> status;
    late bool gpsOn;
    late int settingsOpened;
    late LocationService service;

    setUp(() {
      registerServices();
      permissions = locator<AppPermissions>() as MockAppPermissions;
      when(permissions.ensure(any, interactive: anyNamed('interactive')))
          .thenAnswer((_) async => PermissionOutcome.granted);
      positionStreams = [];
      status = StreamController<ServiceStatus>.broadcast();
      gpsOn = true;
      settingsOpened = 0;
      service = LocationService(
        positionStreamFactory: (_) {
          final c = StreamController<Position>();
          positionStreams.add(c);
          return c.stream;
        },
        serviceStatusStreamFactory: () => status.stream,
        isServiceEnabled: () async => gpsOn,
        openLocationSettings: () async {
          settingsOpened++;
          return true;
        },
      );
    });
    tearDown(() async {
      service.dispose();
      await status.close();
      locator.reset();
    });

    test('si el stream falla por servicio deshabilitado marca la falla',
        () async {
      await service.startTracking();
      expect(service.trackingFailed, isFalse);

      positionStreams.last.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);

      expect(service.trackingFailed, isTrue);
      expect(service.isTracking, isFalse);
      expect(service.serviceDisabled, isTrue);
    });

    test('al volver el servicio reintenta el stream y limpia la falla',
        () async {
      await service.startTracking();
      positionStreams.last.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);
      expect(positionStreams, hasLength(1));

      status.add(ServiceStatus.enabled);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(positionStreams, hasLength(2));
      expect(service.isTracking, isTrue);

      // sigue marcada hasta que llega una posición: ahí se reanuda el envío
      final recibidas = <Position>[];
      service.positionStream.listen(recibidas.add);
      positionStreams.last.add(_pos());
      await Future<void>.delayed(Duration.zero);
      expect(service.trackingFailed, isFalse);
      expect(recibidas, hasLength(1));
    });

    test('apagar el GPS con el stream andando marca la falla', () async {
      await service.startTracking();
      status.add(ServiceStatus.disabled);
      await Future<void>.delayed(Duration.zero);

      expect(service.trackingFailed, isTrue);
      expect(service.isTracking, isFalse);
    });

    test('un permiso denegado en el stream marca la falla de permiso',
        () async {
      await service.startTracking();
      positionStreams.last.addError(const PermissionDeniedException('x'));
      await Future<void>.delayed(Duration.zero);

      expect(service.trackingFailed, isTrue);
      expect(service.locationPermission, PermissionOutcome.denied);
    });

    test('stopTracking limpia la falla y deja de vigilar el servicio',
        () async {
      await service.startTracking();
      positionStreams.last.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);

      await service.stopTracking();
      expect(service.trackingFailed, isFalse);

      status.add(ServiceStatus.enabled);
      await Future<void>.delayed(Duration.zero);
      expect(positionStreams, hasLength(1));
    });

    test('abre ajustes de ubicación si el GPS está apagado y los de la app '
        'si falta el permiso', () async {
      await service.startTracking();
      positionStreams.last.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);
      await service.openLocationAlertSettings();
      expect(settingsOpened, 1);

      final sinPermiso = LocationService(
        positionStreamFactory: (_) => const Stream.empty(),
        serviceStatusStreamFactory: () => const Stream.empty(),
        isServiceEnabled: () async => true,
        openLocationSettings: () async => true,
      );
      await sinPermiso.openLocationAlertSettings();
      verify(permissions.openSettings()).called(1);
      sinPermiso.dispose();
    });

    test('un stopTracking durante el reintento no deja un stream colgado',
        () async {
      await service.startTracking();
      positionStreams.last.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);

      final espera = Completer<PermissionOutcome>();
      when(permissions.ensure(any, interactive: anyNamed('interactive')))
          .thenAnswer((_) => espera.future);
      status.add(ServiceStatus.enabled);
      await Future<void>.delayed(Duration.zero);

      await service.stopTracking();
      espera.complete(PermissionOutcome.granted);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(positionStreams, hasLength(1));
      expect(service.isTracking, isFalse);
    });

    test('GPS apagado con el tracking ya caído sigue marcado como falla',
        () async {
      gpsOn = false;
      await service.startTracking();
      expect(service.isTracking, isFalse);

      status.add(ServiceStatus.disabled);
      await Future<void>.delayed(Duration.zero);

      expect(service.trackingFailed, isTrue);
      expect(service.locationUnavailable, isTrue);
    });

    test('con GPS apagado y sin permiso abre primero los ajustes de ubicación',
        () async {
      when(permissions.ensure(any, interactive: anyNamed('interactive')))
          .thenAnswer((_) async => PermissionOutcome.denied);
      gpsOn = false;
      await service.startTracking();

      await service.openLocationAlertSettings();
      expect(settingsOpened, 1);
      verifyNever(permissions.openSettings());
    });

    test('dispose cancela la vigilancia del estado del servicio', () async {
      await service.startTracking();
      expect(status.hasListener, isTrue);
      service.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(status.hasListener, isFalse);
    });
  });
}
