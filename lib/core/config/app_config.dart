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
/// flutter build apk --dart-define=API_BASE_URL=https://api.splg.app
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

  /// `--dart-define=PUSH_ENABLED=false` evita pedir permiso de notificaciones
  /// y registrar el token FCM (recorridos automáticos en simulador, donde el
  /// prompt del sistema tapa la pantalla).
  static const bool pushEnabled =
      bool.fromEnvironment('PUSH_ENABLED', defaultValue: true);

  /// Base de la REST API v1 (`/api/v1/`; ver «Versiones de la API» en el back).
  static String get apiUrl => '$apiBaseUrl/api/v1/';

  /// Namespace de Socket.IO del gateway de choferes.
  static String get driversNamespace => '$apiBaseUrl/drivers';
}
