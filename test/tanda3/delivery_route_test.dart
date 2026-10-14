import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

Position pos(double lat, double lng, {double heading = -1, double speed = 0}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 10, 11),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );

// Pedido en -27.357482,-55.890404.
const origen = LatLng(-27.3671, -55.8961);

Map<String, dynamic> directionsOk() => {
      'status': 'OK',
      'routes': [
        {
          'overview_polyline': {
            'points': Geo.decodePolyline('_p~iF~ps|U').isEmpty
                ? ''
                : '_p~iF~ps|U_ulLnnqC'
          },
          'legs': [
            {
              'distance': {'value': 1628},
              'duration': {'value': 240}
            }
          ],
        }
      ],
    };

SplgRoute? lastRoute;

void main() {
  late MockTripService trips;
  late MockLocationService location;
  late StreamController<Position> positions;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    location = locator<LocationService>() as MockLocationService;
    positions = StreamController<Position>.broadcast();
    when(location.positionStream).thenAnswer((_) => positions.stream);
    when(location.currentPosition).thenReturn(null);
    when(trips.order('o1'))
        .thenAnswer((_) async => trip(status: 'out_for_delivery'));
    when(trips.customerRating(any)).thenAnswer((_) async => null);
  });
  tearDown(() async {
    await positions.close();
    locator.reset();
  });

  DeliveryViewModel build(SplgRouteService routes) => DeliveryViewModel(
        orderId: 'o1',
        trips: trips,
        routes: routes,
        pollInterval: const Duration(hours: 1),
        iconLoader: () async => null,
        goHome: () {},
      );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  test('sin clave: línea recta punteada, aviso una vez y la pantalla sigue',
      () async {
    final logs = <String>[];
    final m = build(SplgRouteService(log: logs.add));
    await m.initialize();
    positions.add(pos(origen.latitude, origen.longitude));
    await settle();
    positions.add(pos(-27.3665, -55.8958));
    await settle();
    expect(m.route!.isFallback, true);
    final line = m.polylines.single;
    expect(line.patterns, isNotEmpty);
    expect(line.points.first, const LatLng(-27.3665, -55.8958));
    expect(line.points.last, const LatLng(-27.357482, -55.890404));
    expect(logs.length, 1);
    expect(m.etaText, isNull);
    expect(m.tripSummary, matches(r'^\d[\d,]* (km|m)$'));
    m.dispose();
  });

  test('con ruta por calles: polyline sólida, ETA y distancia', () async {
    var calls = 0;
    final m = build(SplgRouteService(
        directionsKey: 'K',
        fetch: (_) async {
          calls++;
          return directionsOk();
        }));
    await m.initialize();
    positions.add(pos(38.5, -120.2));
    await settle();
    expect(calls, 1);
    expect(m.route!.source, RouteSource.directions);
    expect(m.polylines.single.patterns, isEmpty);
    expect(m.polylines.single.width, 5);
    expect(m.etaText, isNotNull);
    expect(m.tripSummary, contains(' - '));
    m.dispose();
  });

  test('posiciones sobre la ruta no vuelven a pedirla (throttle)', () async {
    var calls = 0;
    final m = build(SplgRouteService(
        directionsKey: 'K',
        fetch: (_) async {
          calls++;
          return directionsOk();
        }));
    await m.initialize();
    positions.add(pos(38.5, -120.2));
    await settle();
    for (var i = 0; i < 5; i++) {
      positions.add(pos(38.5 + i * 0.0001, -120.2));
      await settle();
    }
    expect(calls, 1);
    m.dispose();
  });

  test('un fallo de Directions cae a la recta sin romper', () async {
    final logs = <String>[];
    final m = build(SplgRouteService(
        directionsKey: 'K',
        log: logs.add,
        fetch: (_) async =>
            {'status': 'REQUEST_DENIED', 'error_message': 'Billing'}));
    await m.initialize();
    positions.add(pos(origen.latitude, origen.longitude));
    await settle();
    expect(m.route!.isFallback, true);
    expect(m.polylines, isNotEmpty);
    expect(logs.single, contains('REQUEST_DENIED'));
    m.dispose();
  });

  test('el rumbo sale del GPS cuando se mueve y de las posiciones cuando no',
      () async {
    final m = build(SplgRouteService());
    await m.initialize();
    positions.add(pos(0, 0, heading: 135, speed: 9));
    await settle();
    expect(m.vehicleHeading, 135);
    positions.add(pos(0, 0.001, heading: -1, speed: 0));
    await settle();
    expect(m.vehicleHeading, closeTo(90, 0.5));
    m.dispose();
  });

  test('la cámara deja de seguir al tocar el mapa y recentra con el botón',
      () async {
    final m = build(SplgRouteService());
    await m.initialize();
    expect(m.followCamera, true);
    m.userMovedMap();
    expect(m.followCamera, false);
    await m.recenter();
    expect(m.followCamera, true);
    m.dispose();
  });

  test('sin coordenadas en el pedido no hay ruta ni se pide nada', () async {
    when(trips.order('o1')).thenAnswer((_) async {
      final j = orderJson(status: 'out_for_delivery');
      (j['delivery_address'] as Map).remove('latitude');
      (j['delivery_address'] as Map).remove('longitude');
      return TripOrderFromJson.of(j);
    });
    var calls = 0;
    final m = build(SplgRouteService(
        directionsKey: 'K',
        fetch: (_) async {
          calls++;
          return directionsOk();
        }));
    await m.initialize();
    positions.add(pos(origen.latitude, origen.longitude));
    await settle();
    expect(calls, 0);
    expect(m.polylines, isEmpty);
    expect(m.distanceText, isNull);
    m.dispose();
  });

  group('ruta por el back (GET /routes/driving)', () {
    const rutaBack = {
      'provider': 'google',
      'distanceMeters': 1500,
      'durationSeconds': 200,
      'points': [
        {'lat': -27.3671, 'lng': -55.8961},
        {'lat': -27.362, 'lng': -55.893},
        {'lat': -27.357482, 'lng': -55.890404},
      ],
    };

    Future<List<String>> run(String status, {Object? error}) async {
      final paths = <String>[];
      when(trips.order('o1')).thenAnswer((_) async => trip(status: status));
      when(locator<DriverAuthService>().token).thenAnswer((_) async => 'tok');
      final m = DeliveryViewModel(
        orderId: 'o1',
        trips: trips,
        routeGet: (path, token) async {
          paths.add('$path|$token');
          if (error != null) throw error;
          return Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 200,
              data: rutaBack);
        },
        pollInterval: const Duration(hours: 1),
        iconLoader: () async => null,
        goHome: () {},
      );
      await m.initialize();
      positions.add(pos(origen.latitude, origen.longitude));
      await settle();
      lastRoute = m.route;
      m.dispose();
      return paths;
    }

    test('en camino: pide la ruta al back con el token y la dibuja', () async {
      final paths = await run('out_for_delivery');
      expect(paths, ['routes/driving?orderId=o1|tok']);
      expect(lastRoute!.isFallback, false);
      expect(lastRoute!.source, RouteSource.directions);
      expect(lastRoute!.points, hasLength(3));
    });

    test('aceptado: el back también la da al chofer asignado', () async {
      final paths = await run('accepted');
      expect(paths, hasLength(1));
      expect(lastRoute!.isFallback, false);
    });

    test('entregado: no pregunta', () async {
      final paths = await run('delivered');
      expect(paths, isEmpty);
    });

    test('si el back falla, recta sin romper', () async {
      final paths = await run('out_for_delivery',
          error: DioException(
              requestOptions: RequestOptions(path: 'x'),
              type: DioExceptionType.connectionError));
      expect(paths, hasLength(1));
      expect(lastRoute!.isFallback, true);
    });
  });

  group('posición al back desde la pantalla del pedido', () {
    late MockDriverSocketService socket;
    setUp(() {
      socket = locator<DriverSocketService>() as MockDriverSocketService;
      when(socket.isConnected).thenReturn(true);
      when(locator<DriverAuthService>().userId).thenReturn('u1');
      when(locator<DriverAuthService>().token).thenAnswer((_) async => 'tok');
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'accepted'));
    });

    DeliveryViewModel make({
      Future<Response<dynamic>> Function(String, String)? routeGet,
    }) =>
        DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          routeGet: routeGet ?? (p, t) async => throw UnimplementedError(),
          noPositionRetry: const Duration(milliseconds: 20),
          pollInterval: const Duration(hours: 1),
          iconLoader: () async => null,
          goHome: () {},
        );

    test('cada posición se manda por driver:update-location', () async {
      final m = make();
      await m.initialize();
      positions.add(pos(-27.3671, -55.8961));
      await settle();
      positions.add(pos(-27.3665, -55.8958));
      await settle();
      verify(socket.sendLocation('u1', -27.3671, -55.8961))
          .called(greaterThan(0));
      verify(socket.sendLocation('u1', -27.3665, -55.8958))
          .called(greaterThan(0));
      m.dispose();
    });

    test('al retomar el pedido manda la posición que ya tenía', () async {
      when(location.currentPosition).thenReturn(pos(-27.3671, -55.8961));
      final m = make();
      await m.initialize();
      verify(socket.sendLocation('u1', -27.3671, -55.8961))
          .called(greaterThan(0));
      m.dispose();
    });

    test('socket desconectado: no emite', () async {
      when(socket.isConnected).thenReturn(false);
      final m = make();
      await m.initialize();
      positions.add(pos(-27.3671, -55.8961));
      await settle();
      verifyNever(socket.sendLocation(any, any, any));
      m.dispose();
    });

    test('409 por falta de posición: reintenta la ruta enseguida', () async {
      var calls = 0;
      final m = make(routeGet: (path, token) async {
        calls++;
        if (calls == 1) {
          throw DioException(
              requestOptions: RequestOptions(path: path),
              type: DioExceptionType.badResponse,
              response: Response(
                  requestOptions: RequestOptions(path: path), statusCode: 409));
        }
        return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'provider': 'osrm',
              'points': [
                {'lat': -27.3671, 'lng': -55.8961},
                {'lat': -27.357482, 'lng': -55.890404},
              ],
            });
      });
      await m.initialize();
      positions.add(pos(-27.3671, -55.8961));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 2);
      expect(m.route!.isFallback, false);
      m.dispose();
    });
  });

  test('un fallo al dibujar el ícono no rompe la pantalla', () async {
    final m = DeliveryViewModel(
        orderId: 'o1',
        trips: trips,
        routes: SplgRouteService(),
        pollInterval: const Duration(hours: 1),
        iconLoader: () async => throw Exception('sin canvas'),
        goHome: () {});
    await m.initialize();
    await settle();
    expect(m.vehicleIcon, isNull);
    expect(m.order, isNotNull);
    m.dispose();
  });
}
