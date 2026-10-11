import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Con qué mapa se hace el recorrido del pedido.
enum MapApp { stay, google, waze }

/// Cómo terminó el intento de abrir un mapa externo.
enum MapLaunch {
  /// Se abrió la app instalada.
  app,

  /// La app no está instalada: se abrió la versión web.
  web,

  /// No se pudo abrir nada.
  failed,
}

/// Abre las apps externas de navegación (Google Maps / Waze) con el destino del
/// pedido. Intenta la app instalada y, si no está, cae a la web. No mantiene
/// estado: arma las URLs y delega en `url_launcher`.
class NavigationLauncher {
  NavigationLauncher._();

  /// Sólo para tests: reemplaza a `launchUrl`.
  @visibleForTesting
  static Future<bool> Function(Uri uri)? launcher;

  static Future<bool> _launch(Uri uri) async {
    try {
      final f = launcher;
      if (f != null) return await f(uri);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      log('No se pudo abrir $uri: $e', name: 'NavigationLauncher');
      return false;
    }
  }

  /// URL de la app instalada (esquema propio) y de la web, por mapa.
  @visibleForTesting
  static (Uri app, Uri web) urls(MapApp map, double lat, double lng) {
    switch (map) {
      case MapApp.google:
        final app = defaultTargetPlatform == TargetPlatform.android
            ? Uri.parse('google.navigation:q=$lat,$lng')
            : Uri.parse(
                'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
        return (
          app,
          Uri.parse(
              'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng')
        );
      case MapApp.waze:
        return (
          Uri.parse('waze://?ll=$lat,$lng&navigate=yes'),
          Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes')
        );
      case MapApp.stay:
        throw ArgumentError('MapApp.stay no abre nada externo');
    }
  }

  /// Abre [map] hacia [lat]/[lng]. `MapApp.stay` no hace nada (devuelve `app`).
  static Future<MapLaunch> open(MapApp map, double lat, double lng) async {
    if (map == MapApp.stay) return MapLaunch.app;
    final (app, web) = urls(map, lat, lng);
    if (await _launch(app)) return MapLaunch.app;
    if (await _launch(web)) return MapLaunch.web;
    return MapLaunch.failed;
  }

  /// Abre el teléfono con el número del cliente (`tel:`).
  static Future<bool> dial(String phone) {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return _launch(Uri(scheme: 'tel', path: clean));
  }

  /// Texto para avisar cuándo se abrió la web en vez de la app.
  static String webNotice(MapApp map) => map == MapApp.waze
      ? 'No tenés Waze instalado: abrimos la versión web.'
      : 'No tenés Google Maps instalado: abrimos la versión web.';
}
