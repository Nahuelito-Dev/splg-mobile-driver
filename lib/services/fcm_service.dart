import 'dart:async';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/config/app_config.dart';
import 'package:splg_driver/services/app_permissions.dart';
import 'package:splg_lib/permissions/app_permission.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/services/driver_auth_service.dart';

/// Handler de mensajes FCM en background/terminated. Tiene que ser una
/// función top-level (o estática) con `@pragma('vm:entry-point')` porque
/// corre en un isolate aparte cuando la app está cerrada/en background.
///
/// Hoy no hace nada además de loguear: los mensajes de tipo `notification`
/// los muestra el sistema operativo automáticamente sin código nuestro; esto
/// solo cubre mensajes data-only para no perderlos silenciosamente.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('Mensaje FCM en background: ${message.messageId}', name: 'FcmService');
}

/// Notificaciones push (FCM) para el chofer.
///
/// Complementa —no reemplaza— al canal de ofertas por WebSocket
/// ([DriverSocketService]): mientras el chofer está conectado y con la app
/// abierta, las ofertas siguen llegando por socket en tiempo real. FCM cubre
/// el caso en que la app está cerrada/en background y el socket no está vivo,
/// para no perder la notificación de que hay un pedido esperando.
///
/// Flujo:
/// 1. Al loguearse (o restaurar sesión), pedimos permiso, obtenemos el token
///    del dispositivo y lo registramos en el backend (`POST /notifications/token`).
/// 2. `onTokenRefresh` re-registra automáticamente si el token cambia (puede
///    pasar en cualquier momento, no solo en el login).
/// 3. En foreground, como iOS/Android no muestran la notificación del sistema
///    solos, disparamos una notificación local con `flutter_local_notifications`.
///
/// NOTA (bloqueo conocido): en iOS el push real requiere que el certificado
/// APNs (.p8) esté subido en Firebase Console — está pendiente de que el
/// dueño del proyecto lo suba. Sin eso, `getToken()` en iOS puede fallar o
/// nunca disparar `onMessage`; en Android funciona sin dependencias externas.
class FcmService {
  final _apiClient = ApiClient();
  final _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  bool _initialized = false;

  static const _channelId = 'splg_driver_offers';
  static const _channelName = 'SPLG Chofer — Ofertas de pedido';

  /// Inicializa `flutter_local_notifications` (canal de Android + config de
  /// iOS) y engancha el listener de mensajes en foreground. Idempotente.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Avisos de nuevos pedidos ofertados al chofer.',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription =
        FirebaseMessaging.onMessage.listen(_showForegroundNotification);
  }

  /// Muestra un aviso local cuando llega un mensaje FCM con la app abierta
  /// (en foreground el sistema operativo no lo muestra solo).
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    try {
      await _localNotifications.show(
        message.hashCode,
        notification.title ?? 'SPLG Chofer',
        notification.body ?? 'Tenés un nuevo aviso.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      log('Error mostrando notificación local: $e', name: 'FcmService');
    }
  }

  /// Pide permiso, obtiene el token FCM del dispositivo y lo registra en el
  /// backend para el chofer logueado (`_authService.userId`). Además deja
  /// enganchado `onTokenRefresh` para re-registrar si el token cambia.
  ///
  /// [interactive] false (reapertura de la app con sesión) sólo registra si el
  /// permiso ya estaba concedido; true (login) lo pide con explicación previa.
  ///
  /// Best-effort: si algo falla (sin permiso, sin sesión, error de red), se
  /// loguea y no bloquea el resto del flujo de la app.
  Future<void> registerForCurrentUser(
    DriverAuthService authService, {
    bool interactive = true,
  }) async {
    if (!AppConfig.pushEnabled) return;
    try {
      await _ensureInitialized();

      final outcome = await locator<AppPermissions>().ensure(
        AppPermission.notifications,
        interactive: interactive,
      );
      if (!outcome.isGranted) {
        log('Notificaciones sin permiso ($outcome): no se registra el token',
            name: 'FcmService');
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _sendTokenToBackend(authService, token);
      }

      _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
          .listen((newToken) => _sendTokenToBackend(authService, newToken));
    } catch (e) {
      log('Error registrando token FCM: $e', name: 'FcmService');
    }
  }

  /// `POST /notifications/token` con el mismo shape que usa la app cliente:
  /// `{ userId, token, platform }`.
  Future<void> _sendTokenToBackend(
    DriverAuthService authService,
    String token,
  ) async {
    final userId = authService.userId;
    if (userId == null) {
      log('No se registra token FCM: no hay sesión de chofer activa',
          name: 'FcmService');
      return;
    }

    try {
      final apiToken = await authService.token;
      await _apiClient.post(
        'notifications/token',
        {
          'userId': userId,
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
        apiToken,
      );
      log('Token FCM registrado para userId=$userId', name: 'FcmService');
    } catch (e) {
      // Best-effort: el endpoint hoy solo persiste el token para clientes
      // (Customer), no para choferes (Delivery) — ver nota en el PR/commit.
      // Igual lo intentamos siempre, para que ande apenas el backend lo
      // soporte, sin tener que tocar la app de nuevo.
      log('Error registrando token FCM en el backend: $e', name: 'FcmService');
    }
  }

  /// Libera las suscripciones activas.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
  }
}
