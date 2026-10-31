import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';

import 'helpers/test_helpers.dart';

Position pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 10, 11),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: -1,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// El mapa del Inicio se centra solo en el chofer (al abrir y cuando se
/// mueve), sin pelear con el usuario que lo arrastró.
void main() {
  setUp(() => registerServices());
  tearDown(() => locator.reset());

  test('se centra al abrir y acompaña los movimientos', () {
    final moves = <LatLng>[];
    var now = DateTime(2026, 10, 11, 10);
    final m = HomeViewModel()
      ..now = (() => now)
      ..cameraMover = (p) async => moves.add(p);
    m.onData(pos(-27.36, -55.89));
    m.onData(pos(-27.37, -55.90));
    expect(moves, [const LatLng(-27.36, -55.89), const LatLng(-27.37, -55.90)]);
  });

  test('si el usuario tocó el mapa no se lo pelea, y vuelve a seguir después',
      () {
    final moves = <LatLng>[];
    var now = DateTime(2026, 10, 11, 10);
    final m = HomeViewModel()
      ..now = (() => now)
      ..cameraMover = (p) async => moves.add(p);
    m.onData(pos(-27.36, -55.89));
    moves.clear();

    m.onMapTouched();
    now = now.add(const Duration(seconds: 5));
    m.onData(pos(-27.37, -55.90));
    expect(moves, isEmpty, reason: 'lo está explorando');

    now = now.add(HomeViewModel.exploreGrace);
    m.onData(pos(-27.38, -55.91));
    expect(moves, [const LatLng(-27.38, -55.91)]);
  });

  test('el primer fijo centra aunque el usuario ya haya tocado el mapa', () {
    final moves = <LatLng>[];
    final m = HomeViewModel()..cameraMover = (p) async => moves.add(p);
    m.onMapTouched();
    m.onData(pos(-27.36, -55.89));
    expect(moves, hasLength(1));
  });
}
