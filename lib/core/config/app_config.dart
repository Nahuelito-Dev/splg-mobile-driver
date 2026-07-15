/// Configuración de entorno centralizada de la app chofer.
///
/// La URL base del backend se resuelve en tiempo de compilación con
/// `--dart-define`, así el mismo código sirve para emulador, dispositivo físico
/// y producción sin hardcodear nada:
///
/// ```bash
/// # Emulador Android (default): 10.0.2.2 = localhost del host
/// flutter run
/// # Dispositivo físico en la LAN:
/// flutter run --dart-define=API_BASE_URL=http://192.168.0.20:3000
/// # Producción:
/// flutter build apk --dart-define=API_BASE_URL=https://api.jennygas.com
/// ```
class AppConfig {
  const AppConfig._();

  /// Host + puerto del backend (SIN el sufijo `/api`). Overridable por build.
  /// Default: `10.0.2.2` = localhost de la máquina de desarrollo visto desde el
  /// emulador Android (en el emulador `localhost` apunta al propio Android).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Base de la REST API (con `/api`).
  static String get apiUrl => '$apiBaseUrl/api/';

  /// Namespace de Socket.IO del gateway de choferes.
  static String get driversNamespace => '$apiBaseUrl/drivers';
}
