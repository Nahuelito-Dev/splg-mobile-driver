import 'dart:async';
import 'dart:developer';

import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:stacked/stacked.dart';

import 'package:driver_mobile/app/app.locator.dart';
import 'package:driver_mobile/core/config/app_config.dart';
import 'package:driver_mobile/services/location_service.dart';

/// Namespace de Socket.IO donde el backend expone el gateway de choferes.
/// La URL base está centralizada en [AppConfig] (configurable por build).
final String _kDriversNamespace = AppConfig.driversNamespace;

/// Service encargado del canal de tiempo real con el backend para el
/// tracking en vivo del chofer: abre la conexión Socket.IO al namespace
/// `drivers`, se autentica con el token de Firebase del chofer y emite su
/// posición GPS a medida que el [LocationService] la va reportando.
///
/// Uso esperado desde una vista/viewmodel de entrega activa:
/// ```dart
/// final token = await FirebaseAuth.instance.currentUser?.getIdToken();
/// locator<DriverSocketService>().startBroadcasting(orderId, userId, token!);
/// // ... al finalizar/cancelar la entrega, o al salir de la vista:
/// locator<DriverSocketService>().stopBroadcasting();
/// ```
class DriverSocketService with ListenableServiceMixin {
  DriverSocketService() {
    listenToReactiveValues([_isConnected]);
  }

  final _locationService = locator<LocationService>();

  io.Socket? _socket;
  StreamSubscription<Position>? _positionSubscription;

  final ReactiveValue<bool> _isConnected = ReactiveValue<bool>(false);

  /// Indica si el socket está conectado y el `driver:join` ya fue emitido.
  bool get isConnected => _isConnected.value;

  /// Ofertas de pedido que el backend empuja mientras el chofer está
  /// conectado (evento `server:new-order-request`). Cada item es el payload
  /// crudo tal cual lo manda el gateway, con forma
  /// `{ event: 'NEW_ORDER' | 'NEW_ORDER_RETRY', orderId, totalAmount,
  /// paymentMethod, expiresAt, items }`.
  ///
  /// Es un stream broadcast que sobrevive a reconexiones del socket (no se
  /// cierra en [disconnect], solo en [dispose]).
  final _incomingOrdersController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingOrders =>
      _incomingOrdersController.stream;

  /// orderId de la entrega para la que se está emitiendo posición
  /// actualmente (null si no hay broadcasting activo).
  String? _activeOrderId;
  String? get activeOrderId => _activeOrderId;

  /// Abre la conexión Socket.IO contra el namespace `drivers` del backend,
  /// autenticando con el token de Firebase del chofer (se manda tanto en
  /// `auth.token` como en el header `Authorization`, porque el gateway
  /// valida ambos). Al conectar, emite `driver:join` con el `driverId`.
  ///
  /// Si ya existe una conexión abierta no hace nada (usar [disconnect]
  /// primero si se necesita reconectar con otro token/driverId).
  void connect(String token, String driverId) {
    if (_socket != null) {
      log('connect() ignorado: ya existe una conexión de socket activa',
          name: 'DriverSocketService');
      return;
    }

    log('Conectando a $_kDriversNamespace', name: 'DriverSocketService');

    final socket = io.io(
      _kDriversNamespace,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .enableReconnection()
          .enableForceNew()
          .build(),
    );
    _socket = socket;

    // Se registra una sola vez por conexión; sobrevive a reconexiones
    // automáticas del propio socket.io-client.
    socket.on('server:new-order-request', (data) {
      if (data is Map) {
        log('Oferta de pedido recibida: $data', name: 'DriverSocketService');
        _incomingOrdersController.add(Map<String, dynamic>.from(data));
      } else {
        log('Payload inesperado en server:new-order-request: $data',
            name: 'DriverSocketService');
      }
    });

    socket.onConnect((_) {
      _isConnected.value = true;
      log('Conectado (driverId=$driverId), emitiendo driver:join',
          name: 'DriverSocketService');
      socket.emit('driver:join', {'driverId': driverId});
    });

    socket.onDisconnect((_) {
      _isConnected.value = false;
      log('Desconectado', name: 'DriverSocketService');
    });

    socket.onConnectError((error) {
      log('Error de conexión: $error', name: 'DriverSocketService');
    });

    socket.onError((error) {
      log('Error de socket: $error', name: 'DriverSocketService');
    });

    socket.onReconnect((_) {
      log('Reconectado, re-emitiendo driver:join', name: 'DriverSocketService');
      socket.emit('driver:join', {'driverId': driverId});
    });

    socket.connect();
  }

  /// Emite la posición actual del chofer al backend (`driver:update-location`).
  /// No hace nada si el socket todavía no está conectado.
  void sendLocation(String userId, double lat, double lng) {
    final socket = _socket;
    if (socket == null || !_isConnected.value) {
      log('sendLocation() ignorado: socket no conectado',
          name: 'DriverSocketService');
      return;
    }

    socket.emit('driver:update-location', {
      'userId': userId,
      'lat': lat,
      'lng': lng,
    });
  }

  /// Conecta el socket (ver [connect]) y se suscribe al `positionStream`
  /// del [LocationService] para emitir automáticamente cada nueva posición
  /// mientras dure la entrega activa.
  ///
  /// Debe invocarse cuando el chofer arranca una entrega (por ejemplo, al
  /// tocar "Iniciar viaje" en la pantalla de detalle de la orden en curso),
  /// y requiere que [LocationService.startTracking] esté activo (o se
  /// active en simultáneo) para que el stream de posiciones emita valores.
  ///
  /// - [orderId]: id de la entrega en curso (informativo/para logging; hoy
  ///   el backend no lo necesita en el payload de `driver:update-location`).
  /// - [userId]: id del chofer logueado (el mismo que se usa como
  ///   `driverId` en `driver:join`).
  /// - [token]: ID token de Firebase vigente del chofer
  ///   (`FirebaseAuth.instance.currentUser?.getIdToken()`).
  void startBroadcasting(String orderId, String userId, String token) {
    _activeOrderId = orderId;
    connect(token, userId);

    _positionSubscription?.cancel();
    _positionSubscription = _locationService.positionStream.listen(
      (position) {
        sendLocation(userId, position.latitude, position.longitude);
      },
      onError: (error) {
        log('Error en el stream de posición: $error',
            name: 'DriverSocketService');
      },
    );

    log('Broadcasting iniciado para orderId=$orderId',
        name: 'DriverSocketService');
  }

  /// Detiene el envío de posición para la entrega activa y cierra el socket.
  void stopBroadcasting() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _activeOrderId = null;
    disconnect();
    log('Broadcasting detenido', name: 'DriverSocketService');
  }

  /// Cierra la conexión de socket y limpia todos sus listeners.
  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _isConnected.value = false;
  }

  /// Limpia recursos al destruir el servicio.
  void dispose() {
    _positionSubscription?.cancel();
    disconnect();
    _incomingOrdersController.close();
  }
}
