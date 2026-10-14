import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splg_driver/services/backend_route_service.dart';
import 'package:splg_lib/maps/route_service.dart';

const _from = LatLng(-27.36, -55.89);
const _to = LatLng(-27.37, -55.90);

/// Lo que responde `GET /routes/driving` (docs/PEDIDOS.md del back).
const _ruta = {
  'provider': 'osrm',
  'distanceMeters': 4621,
  'durationSeconds': 465,
  'encodedPolyline': 'xx',
  'points': [
    {'lat': -27.36, 'lng': -55.89},
    {'lat': -27.365, 'lng': -55.895},
    {'lat': -27.37, 'lng': -55.90},
  ],
};

Response<dynamic> _ok(Object data) => Response(
    requestOptions: RequestOptions(path: 'x'), statusCode: 200, data: data);

DioException _fail(int status, {Map<String, dynamic>? headers}) {
  final req = RequestOptions(path: 'x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: req,
      statusCode: status,
      data: {'message': 'x'},
      headers: Headers.fromMap({
        for (final e in (headers ?? {}).entries) e.key: [e.value.toString()],
      }),
    ),
  );
}

void main() {
  late List<String> paths;
  late DateTime clock;

  BackendRouteService service(
    Future<Response<dynamic>> Function() answer, {
    bool Function()? canRequest,
    Future<String?> Function()? token,
  }) =>
      BackendRouteService(
        orderId: 'o1',
        tokenProvider: token ?? () async => 'tok',
        canRequest: canRequest,
        get: (path, tok) {
          paths.add('$path|$tok');
          return answer();
        },
        now: () => clock,
      );

  setUp(() {
    paths = [];
    clock = DateTime(2026, 10, 14, 12);
  });

  test('pide la ruta al back por pedido, sin destino ni clave de mapas',
      () async {
    final s = service(() async => _ok(_ruta));

    final route = await s.route(_from, _to);

    expect(paths.single, 'routes/driving?orderId=o1|tok');
    expect(route.isFallback, isFalse);
    expect(route.points, hasLength(3));
    expect(route.distanceMeters, 4621);
    expect(route.durationSeconds, 465);
    expect(route.source, RouteSource.osrm);
  });

  test('si el proveedor del back es directions lo informa', () async {
    final s = service(() async => _ok({..._ruta, 'provider': 'google'}));
    expect((await s.route(_from, _to)).source, RouteSource.directions);
  });

  test('429 cae a la línea recta sin lanzar y espera antes de insistir',
      () async {
    final s = service(() async => throw _fail(429));

    final first = await s.route(_from, _to);
    final second = await s.route(_from, _to);

    expect(first.isFallback, isTrue);
    expect(second.isFallback, isTrue);
    expect(paths, hasLength(1));

    clock = clock.add(
        BackendRouteService.tooManyRequestsPause + const Duration(seconds: 1));
    await s.route(_from, _to);
    expect(paths, hasLength(2));
  });

  test('respeta Retry-After del 429', () async {
    final s =
        service(() async => throw _fail(429, headers: {'retry-after': '300'}));

    await s.route(_from, _to);
    clock = clock.add(const Duration(minutes: 4));
    await s.route(_from, _to);
    expect(paths, hasLength(1));

    clock = clock.add(const Duration(minutes: 2));
    await s.route(_from, _to);
    expect(paths, hasLength(2));
  });

  test('502, 503 y 500 caen a la recta y dejan de insistir un rato', () async {
    for (final status in [502, 503, 500]) {
      paths.clear();
      final s = service(() async => throw _fail(status));
      expect((await s.route(_from, _to)).isFallback, isTrue);
      await s.route(_from, _to);
      expect(paths, hasLength(1), reason: 'status $status');
    }
  });

  test(
      '403, 404, 409 y 400 caen a la recta (el pedido no está en camino o '
      'sin posición reciente)', () async {
    for (final status in [400, 403, 404, 409]) {
      final s = service(() async => throw _fail(status));
      final route = await s.route(_from, _to);
      expect(route.isFallback, isTrue, reason: 'status $status');
      expect(route.points, [_from, _to]);
    }
  });

  test('sin red o con una respuesta ilegible, recta', () async {
    expect(
        (await service(() async => throw DioException(
                requestOptions: RequestOptions(path: 'x'),
                type: DioExceptionType.connectionError)).route(_from, _to))
            .isFallback,
        isTrue);
    expect(
        (await service(() async => _ok({'points': 'mal'})).route(_from, _to))
            .isFallback,
        isTrue);
    expect(
        (await service(() async => _ok({
                  'points': [
                    {'lat': 1, 'lng': 2}
                  ]
                })).route(_from, _to))
            .isFallback,
        isTrue);
  });

  test('si el pedido no está aceptado ni en camino ni pregunta', () async {
    final s = service(() async => _ok(_ruta), canRequest: () => false);

    final route = await s.route(_from, _to);

    expect(route.isFallback, isTrue);
    expect(paths, isEmpty);
  });

  test('sin sesión no pregunta', () async {
    final s = service(() async => _ok(_ruta), token: () async => null);
    expect((await s.route(_from, _to)).isFallback, isTrue);
    expect(paths, isEmpty);
  });

  test('la app no lleva clave de Google ni le pega a Google/OSRM', () {
    final prohibido = [
      'DIRECTIONS_API_KEY',
      'directionsApiKey',
      'ROUTE_PROVIDER',
      'maps.googleapis.com/maps/api/directions',
      'router.project-osrm.org',
      'SplgRouteService(',
    ];
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      for (final word in prohibido) {
        if (text.contains(word)) offenders.add('${f.path}: $word');
      }
    }
    expect(offenders, isEmpty);
  });
}
