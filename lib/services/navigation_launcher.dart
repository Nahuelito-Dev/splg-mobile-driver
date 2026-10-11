import 'dart:developer';

import 'package:url_launcher/url_launcher.dart';

/// Helper para abrir apps externas de navegación (Waze / Google Maps) con
/// el destino de la entrega. No depende del locator/Stacked porque no
/// mantiene estado: son funciones puras que arman la URL y delegan en
/// `url_launcher`.
class NavigationLauncher {
  /// Abre Waze con navegación directa hacia [lat]/[lng].
  static Future<bool> openWaze(double lat, double lng) {
    final uri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
    return _launch(uri, appName: 'Waze');
  }

  /// Abre Google Maps con la ruta hacia [lat]/[lng].
  static Future<bool> openGoogleMaps(double lat, double lng) {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    return _launch(uri, appName: 'Google Maps');
  }

  static Future<bool> _launch(Uri uri, {required String appName}) async {
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        log('No se pudo abrir $appName ($uri)', name: 'NavigationLauncher');
      }
      return launched;
    } catch (e) {
      log('Error al abrir $appName: $e', name: 'NavigationLauncher');
      return false;
    }
  }
}
