import 'dart:async';
import 'dart:developer';
import 'dart:math' show Random, min, pow;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/config/app_config.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/location_service.dart';

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
  DriverSocketService({
    Future<String?> Function()? tokenProvider,
    @visibleForTesting
    io.Socket Function(String uri, Map<String, dynamic> opts)? socketFactory,
    @visibleForTesting DateTime Function()? now,
    @visibleForTesting Random? random,
  })  : _tokenProvider = tokenProvider,
        _socketFactory = socketFactory,
        _now = now ?? DateTime.now,
        _random = random ?? Random() {
    listenToReactiveValues([_isConnected]);
  }

  /// Token de Firebase vigente. El del handshake vence a la hora: cada vez que
  /// hay que volver a conectar se pide uno nuevo en vez de reusar el primero.
  final Future<String?> Function()? _tokenProvider;
  final io.Socket Function(String uri, Map<String, dynamic> opts)?
      _socketFactory;
  bool _refreshing = false;

  final DateTime Function() _now;
  final Random _random;

  /// Reintentos tras un corte: espera exponencial con tope y jitter. Sin esto
  /// un servidor que corta siempre (chofer bloqueado, sin usuario, base caída)
  /// recibía miles de conexiones por segundo.
  static const Duration reconnectBase = Duration(seconds: 1);
  static const Duration reconnectMax = Duration(seconds: 60);

  /// Una conexión que dura menos que esto cuenta como un rechazo.
  static const Duration stableAfter = Duration(seconds: 10);

  /// Cortes seguidos del servidor, sin llegar a estabilizarse, tras los cuales
  /// se deja de insistir y se avisa por [rejected].
  static const int maxServerCuts = 6;

  int _attempts = 0;
  int _serverCuts = 0;
  DateTime? _connectedAt;
  Timer? _retryTimer;
  bool _gaveUp = false;

  /// El back avisó que bloqueó o dio de baja la cuenta (`server:access-revoked`):
  /// el corte que sigue no se reintenta.
  bool _accessRevoked = false;

  /// El último corte fue porque se bloqueó o se dio de baja la cuenta.
  bool get accessRevoked => _accessRevoked;

  final _rejectedController = StreamController<void>.broadcast();

  /// El servidor cortó varias veces seguidas apenas conectar (la sesión no es
  /// válida: cuenta inhabilitada, sin usuario…): se dejó de reconectar y la app
  /// tiene que avisar y pedir iniciar sesión de nuevo.
  Stream<void> get rejected => _rejectedController.stream;

  /// Espera antes del intento [attempt] (0 = el primero): 1 s, 2 s, 4 s… hasta
  /// [reconnectMax], con jitter de 50 % a 100 %.
  @visibleForTesting
  Duration backoff(int attempt) {
    final exp = reconnectBase.inMilliseconds * pow(2, attempt.clamp(0, 20));
    final capped = min(exp.toDouble(), reconnectMax.inMilliseconds.toDouble());
    return Duration(
        milliseconds: (capped * (0.5 + _random.nextDouble() / 2)).round());
  }

  void _scheduleReconnect() {
    if (_gaveUp || _retryTimer?.isActive == true || _socket == null) return;
    final wait = backoff(_attempts++);
    _retryTimer = Timer(wait, () {
      _retryTimer = null;
      unawaited(ensureConnected());
    });
  }

  Future<String?> _freshToken() =>
      (_tokenProvider ?? () => locator<DriverAuthService>().token)();

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

  /// Avisos de cancelación del pedido en curso (`order:cancelled`): lo cancela
  /// el cliente o el panel mientras el chofer lo tiene asignado.
  final _cancelledController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get orderCancelled =>
      _cancelledController.stream;

  /// El cliente cambió la dirección de entrega del pedido en curso
  /// (`order:address-changed`): hay que releerlo y rehacer la ruta.
  final _addressChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get orderAddressChanged =>
      _addressChangedController.stream;

  /// El cliente erró el código de entrega (`order:delivery-code-failed`) o lo
  /// bloqueó (`order:delivery-code-blocked`): trae `orderId`, `attempts`,
  /// `maxAttempts` y `blocked`.
  final _deliveryCodeController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get deliveryCodeFailed =>
      _deliveryCodeController.stream;

  /// Avisos del planificador de taller (CU-105): propuesta nueva o cerrada,
  /// ventana confirmada y caso escalado.
  final _maintenanceController = StreamController<MaintenanceEvent>.broadcast();
  Stream<MaintenanceEvent> get maintenanceEvents =>
      _maintenanceController.stream;

  /// Avisos de los recorridos (CU-107): oferta nueva, oferta cerrada y pedidos
  /// asignados al aceptar.
  final _routeBatchController = StreamController<RouteBatchEvent>.broadcast();
  Stream<RouteBatchEvent> get routeBatchEvents => _routeBatchController.stream;

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

    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .setAuth({'token': token})
        .setExtraHeaders({'Authorization': 'Bearer $token'})
        .enableReconnection()
        .enableForceNew()
        .build();
    final socket = _socketFactory?.call(_kDriversNamespace, options) ??
        io.io(_kDriversNamespace, options);
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

    socket.on('order:cancelled', (data) {
      if (data is Map) {
        _cancelledController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('order:address-changed', (data) {
      if (data is Map) {
        _addressChangedController.add(Map<String, dynamic>.from(data));
      }
    });

    for (final event in const [
      'order:delivery-code-failed',
      'order:delivery-code-blocked',
    ]) {
      socket.on(event, (data) {
        if (data is Map) {
          _deliveryCodeController.add(Map<String, dynamic>.from(data));
        }
      });
    }

    void maintenance(
        String event, MaintenanceEvent? Function(Map<String, dynamic>) parse) {
      socket.on(event, (data) {
        if (data is! Map) return;
        final parsed = parse(Map<String, dynamic>.from(data));
        if (parsed != null) _maintenanceController.add(parsed);
      });
    }

    maintenance('maintenance:proposal', (m) {
      final p = MaintenanceProposal.fromJson(m);
      return p.proposalId.isEmpty ? null : ProposalReceived(p);
    });
    maintenance('maintenance:proposal-closed', (m) {
      final id = m['proposalId']?.toString();
      return id == null ? null : ProposalClosed(id, m['reason']?.toString());
    });
    maintenance('maintenance:window-confirmed',
        (m) => WindowConfirmed(ConfirmedWindow.fromJson(m)));
    maintenance(
        'maintenance:case-escalated',
        (m) => CaseEscalated(
              caseId: m['caseId']?.toString() ?? '',
              taskId: m['taskId']?.toString(),
              taskName: m['taskName']?.toString() ?? 'Mantenimiento',
              patent: m['patent']?.toString(),
              reason: m['reason']?.toString(),
            ));

    for (final event in const [
      'route-batch:offer',
      'route-batch:offer-closed',
      'route-batch:assigned',
    ]) {
      socket.on(event, (data) {
        if (data is! Map) return;
        final parsed =
            parseRouteBatchEvent(event, Map<String, dynamic>.from(data));
        if (parsed != null) _routeBatchController.add(parsed);
      });
    }

    socket.on('server:access-revoked', (_) => _accessRevoked = true);

    socket.onConnect((_) {
      _connectedAt = _now();
      _isConnected.value = true;
      log('Conectado (driverId=$driverId), emitiendo driver:join',
          name: 'DriverSocketService');
      socket.emit('driver:join', {'driverId': driverId});
    });

    socket.onDisconnect((reason) {
      _isConnected.value = false;
      log('Desconectado ($reason)', name: 'DriverSocketService');
      final since = _connectedAt;
      _connectedAt = null;
      if (since != null && _now().difference(since) >= stableAfter) {
        _attempts = 0;
        _serverCuts = 0;
      }
      // Si lo cortó el servidor el cliente no reintenta solo: se reintenta con
      // espera creciente y token nuevo; con varios cortes seguidos se renuncia.
      // (Los demás cortes los reintenta el propio cliente.)
      if (reason == 'io server disconnect') {
        if (_accessRevoked || ++_serverCuts >= maxServerCuts) {
          _gaveUp = true;
          _retryTimer?.cancel();
          _retryTimer = null;
          _rejectedController.add(null);
        } else {
          _scheduleReconnect();
        }
      }
    });

    socket.onConnectError((error) {
      log('Error de conexión: $error', name: 'DriverSocketService');
      // Típico con el token vencido: se renuevan las credenciales y se
      // reintenta con espera creciente.
      _scheduleReconnect();
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

  /// Pone en el socket el token de Firebase actual, tanto en el `auth` del
  /// handshake como en el header `Authorization` (el gateway valida ambos).
  @visibleForTesting
  Future<void> applyFreshToken(io.Socket socket) async {
    final token = await _freshToken();
    if (token == null) return;
    socket.auth = {'token': token};
    socket.io.options?['extraHeaders'] = {'Authorization': 'Bearer $token'};
  }

  /// Si el socket existe y está caído: renueva el token y vuelve a conectar.
  /// Lo usan los errores de conexión y el sondeo del Inicio como respaldo.
  Future<void> ensureConnected() async {
    final socket = _socket;
    if (socket == null ||
        _isConnected.value ||
        _refreshing ||
        _gaveUp ||
        _retryTimer?.isActive == true) {
      return;
    }
    _refreshing = true;
    try {
      await applyFreshToken(socket);
      if (identical(socket, _socket) && !_isConnected.value) socket.connect();
    } catch (e) {
      log('No se pudo renovar el token del socket: $e',
          name: 'DriverSocketService');
    } finally {
      _refreshing = false;
    }
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

  /// Termina el reparto sin tocar la conexión: deja de emitir la posición de la
  /// entrega y el chofer sigue en línea para recibir ofertas.
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _activeOrderId = null;
    log('Tracking de la entrega detenido (sigue conectado)',
        name: 'DriverSocketService');
  }

  /// true si hay un socket abierto o en proceso de conexión (aunque todavía no
  /// haya emitido `driver:join`). Mientras exista, `connect()` se ignora.
  bool get hasSocket => _socket != null;

  /// Espera a que el socket quede conectado (y unido a la sala). `false` si no
  /// lo logra en [timeout].
  Future<bool> waitUntilConnected(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!_isConnected.value) {
      if (_socket == null || DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return true;
  }

  /// Cierra la conexión de socket y limpia todos sus listeners.
  void disconnect() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempts = 0;
    _serverCuts = 0;
    _gaveUp = false;
    _accessRevoked = false;
    _connectedAt = null;
    _socket?.dispose();
    _socket = null;
    _isConnected.value = false;
  }

  /// Limpia recursos al destruir el servicio.
  void dispose() {
    _positionSubscription?.cancel();
    disconnect();
    _incomingOrdersController.close();
    _cancelledController.close();
    _addressChangedController.close();
    _deliveryCodeController.close();
    _maintenanceController.close();
    _routeBatchController.close();
    _rejectedController.close();
  }
}
