import 'package:flutter_test/flutter_test.dart';
import 'package:splg_driver/services/navigation_launcher.dart';

void main() {
  tearDown(() => NavigationLauncher.launcher = null);

  test('si la app está instalada abre la app y no la web', () async {
    final opened = <Uri>[];
    NavigationLauncher.launcher = (u) async {
      opened.add(u);
      return true;
    };
    expect(await NavigationLauncher.open(MapApp.waze, -27.3, -55.9),
        MapLaunch.app);
    expect(opened.single.scheme, 'waze');
    expect(opened.single.toString(), contains('-27.3,-55.9'));
  });

  test('si la app no está instalada cae a la web', () async {
    final opened = <Uri>[];
    NavigationLauncher.launcher = (u) async {
      opened.add(u);
      return u.scheme == 'https';
    };
    expect(await NavigationLauncher.open(MapApp.google, -27.3, -55.9),
        MapLaunch.web);
    expect(opened.length, 2);
    expect(opened.last.host, 'www.google.com');
  });

  test('si no se puede abrir nada, falla', () async {
    NavigationLauncher.launcher = (u) async => false;
    expect(await NavigationLauncher.open(MapApp.waze, 1, 2), MapLaunch.failed);
  });

  test('un launcher que tira excepción cuenta como no abierto', () async {
    NavigationLauncher.launcher = (u) async => throw Exception('x');
    expect(
        await NavigationLauncher.open(MapApp.google, 1, 2), MapLaunch.failed);
  });

  test('"Permanecer en SPLG" no abre nada', () async {
    var calls = 0;
    NavigationLauncher.launcher = (u) async {
      calls++;
      return true;
    };
    await NavigationLauncher.open(MapApp.stay, 1, 2);
    expect(calls, 0);
  });

  test('dial arma tel: con el número limpio', () async {
    Uri? got;
    NavigationLauncher.launcher = (u) async {
      got = u;
      return true;
    };
    await NavigationLauncher.dial('+54 9 381-555 0003');
    expect(got.toString(), 'tel:+5493815550003');
  });
}
