import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splg_driver/core/config/app_config.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.dialogs.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/services/fcm_service.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'package:splg_driver/services/maintenance_repository.dart';
import 'package:splg_driver/services/recovery_repository.dart';
import 'package:splg_driver/services/route_batch_repository.dart';
import 'package:splg_driver/ui/dialogs/route_batch_offer/route_batch_offer_dialog_model.dart'
    show BatchOutcome;
import 'package:splg_driver/services/app_permissions.dart';
import 'package:splg_driver/services/delivery_offer_slot.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/legal/legal_view.dart';
import 'package:splg_lib/permissions/app_permission.dart';

/// Fase de la búsqueda de pedidos mientras el chofer está en línea.
enum HomeSearch {
  /// Fuera de línea.
  idle,

  /// En línea, esperando una oferta ("Buscando pedidos…").
  searching,

  /// En línea y sin ofertas pasado el tiempo de espera ("Sin pedidos disponibles").
  empty,
}

class HomeViewModel extends StreamViewModel<Position>
    with WidgetsBindingObserver {
  HomeViewModel({
    ApiClient? apiClient,
    this.searchTimeout = const Duration(seconds: 6),
    this.loadPollInterval = const Duration(seconds: 20),
    TripService? trips,
    bool Function()? isHomeVisible,
  })  : _apiClient = apiClient ?? ApiClient(),
        _tripsOverride = trips,
        _isHomeVisibleOverride = isHomeVisible;

  final bool Function()? _isHomeVisibleOverride;

  /// El Inicio está al frente: ninguna pantalla (entrega, cobro, calificación,
  /// Mi carga…) se apoya encima. Lo informa la vista con un `RouteAware`; no se
  /// deduce del largo de la pila porque tras iniciar sesión hay rutas debajo.
  bool routeVisible = true;

  bool _isHomeVisible() => _isHomeVisibleOverride?.call() ?? routeVisible;

  /// La vista avisa que el Inicio quedó tapado o volvió a quedar al frente.
  void setRouteVisible(bool visible) {
    if (routeVisible == visible) return;
    routeVisible = visible;
    if (visible) unawaited(refreshNoOrdersReason());
  }

  final TripService? _tripsOverride;

  /// Cuánto se muestra "Buscando pedidos…" antes de pasar a "Sin pedidos
  /// disponibles" si no llegó ninguna oferta.
  final Duration searchTimeout;

  /// Cada cuánto se pregunta al back si el chofer puede recibir pedidos: así
  /// el aviso se va solo cuando el administrador abre la carga.
  final Duration loadPollInterval;

  final _locationService = locator<LocationService>();
  final _navigationService = locator<NavigationService>();
  final _driverSocketService = locator<DriverSocketService>();
  final _dialogService = locator<DialogService>();
  DeliveryOfferSlot get _offerSlot => locator<DeliveryOfferSlot>();
  final _foregroundService = locator<DriverForegroundService>();
  final ApiClient _apiClient;
  final _permissions = locator<AppPermissions>();

  // Lazy a propósito (no como los demás `locator<T>()` de arriba): resolver
  // DriverAuthService dispara `FirebaseAuth.instance` en su constructor, y
  // este ViewModel se instancia cada vez que se construye HomeView (incluso
  // en tests/goldens que no inicializan Firebase). Como getter, solo se
  // resuelve cuando efectivamente se usa (connect/acceptOrder/onData).
  DriverAuthService get _driverAuthService => locator<DriverAuthService>();

  TripService get _trips => _tripsOverride ?? locator<TripService>();

  // Lazy, por lo mismo que `_driverAuthService`.
  MaintenanceBoard get _board => locator<MaintenanceBoard>();
  MaintenanceNotifier get _notifier => locator<MaintenanceNotifier>();
  MaintenanceRepository get _maintenanceRepo =>
      locator<MaintenanceRepository>();
  FcmService get _fcm => locator<FcmService>();
  RouteBatchRepository get _batches => locator<RouteBatchRepository>();
  RecoveryRepository get _recovery => locator<RecoveryRepository>();

  // Lazy, por lo mismo que `_driverAuthService`.
  DriverApiService get _driverApi => locator<DriverApiService>();

  Completer<GoogleMapController> mapController = Completer();

  HomeSearch search = HomeSearch.idle;
  Timer? _searchTimer;

  /// Reloj inyectable para los tests.
  DateTime Function() now = DateTime.now;

  StreamSubscription<Map<String, dynamic>>? _incomingOrdersSubscription;

  /// Por qué el back no le va a dar pedidos por su carga del camión (la
  /// distribuidora exige carga abierta y no tiene, la carga no salió o ya
  /// volvió); null si puede recibir. Es el texto del back, el Inicio lo avisa.
  String? noOrdersReason;
  int _reasonSeq = 0;
  Timer? _loadTimer;

  /// true una vez que el socket de choferes está conectado y el chofer quedó
  /// unido a su sala (`driver:join` emitido).
  bool get isConnected => _driverSocketService.isConnected;

  /// Nombre del chofer logueado (para el drawer). Fallback genérico si aún no
  /// se resolvió el perfil.
  String get driverName => _driverAuthService.fullName ?? 'Chofer';

  /// Posición inicial del mapa mientras no hay GPS: la ciudad de la distribuidora
  /// (`AppConfig.mapFallbackLat/Lng`, Posadas por omisión).
  static CameraPosition get initialPosition => CameraPosition(
        target: LatLng(AppConfig.mapFallbackLat, AppConfig.mapFallbackLng),
        zoom: 14.0,
      );

  Set<Marker> markers = {};
  LatLng? currentLocation;
  bool hasLocationPermission = false;
  String? permissionMessage;

  @override
  Stream<Position> get stream => _locationService.positionStream;

  @override
  void onData(Position? position) {
    if (position != null) {
      _updateUserLocation(position);

      // Si el chofer ya está conectado, cada nueva posición del tracking
      // también se reporta al GEO del backend (además de la que se manda
      // una sola vez al conectar), para que el dispatch siempre lo ubique.
      final userId = _driverAuthService.userId;
      if (isConnected && userId != null) {
        _driverSocketService.sendLocation(
          userId,
          position.latitude,
          position.longitude,
        );
      }
    }
  }

  /// En línea pero sin ubicación llegando al despacho (GPS apagado o permiso
  /// revocado con la app abierta): se avisa y se ofrece ir a Ajustes. Con la
  /// franja de entrega sin permiso a la vista, ésa es la que manda.
  bool get showsLocationAlert =>
      isOnline &&
      hasLocationPermission &&
      _locationService.locationUnavailable &&
      !_foregroundPending;

  /// Entrega en curso sin el servicio en primer plano porque falta el permiso
  /// de ubicación (Android no deja arrancar un servicio de tipo location sin
  /// él). Lo decide sólo [_reconcileOnlineState].
  bool _foregroundPending = false;

  @visibleForTesting
  bool get foregroundPending => _foregroundPending;

  /// Franja roja persistente del Inicio: «no se está enviando tu posición».
  bool get showsNoLocationBanner => _foregroundPending && isOnline;

  void _setForegroundPending(bool pending) {
    if (_foregroundPending == pending) return;
    _foregroundPending = pending;
    notifyListeners();
  }

  /// El chofer tiene una entrega en curso aunque el flujo todavía no se haya
  /// abierto: lo marca la reconexión de quien está repartiendo
  /// (`connect(inDelivery: true)`) y se suelta cuando la entrega termina o el
  /// back dice que no hay ninguna en curso.
  bool _deliveryHold = false;

  /// Hay una entrega en curso EN ESTE MOMENTO.
  bool get _isDelivering => _trips.activeOrderId != null || _deliveryHold;

  /// Arranque en vuelo: una segunda llamada mientras tanto espera la misma.
  Future<bool>? _foregroundStart;

  /// Arranca el servicio en primer plano. Devuelve si quedó corriendo, según
  /// el estado real del plugin al terminar (no lo que respondió `start`).
  Future<bool> _startForegroundService() => _foregroundStart ??=
      _runForegroundStart().whenComplete(() => _foregroundStart = null);

  Future<bool> _runForegroundStart() async {
    final delivering = _isDelivering;
    await _foregroundService.start(
      title: delivering ? 'En reparto' : 'Estás en línea',
      text: delivering ? 'Entrega en curso' : 'Recibiendo pedidos cercanos',
    );
    return _foregroundService.isRunning;
  }

  @visibleForTesting
  Future<bool> startForegroundServiceForTest() => _startForegroundService();

  Future<void>? _reconciling;
  bool _reconcileAgain = false;

  /// ÚNICA fuente de verdad de «en línea + servicio en primer plano + permiso
  /// de ubicación». Se llama al conectar, al volver a la app, al cambiar el
  /// permiso, al terminar una entrega y tras cada intento de arranque.
  ///
  /// (a) sin permiso y sin entrega: si está en línea se lo baja del todo
  ///     (disponible false, socket, servicio) y el Inicio pide el permiso;
  /// (b) sin permiso y con entrega: no se corta la entrega; servicio
  ///     pendiente y franja roja;
  /// (c) con permiso y en línea: si el servicio no corre se arranca (con el
  ///     texto de este momento); si igual no queda corriendo y no hay
  ///     entrega, se lo baja.
  /// Fuera de línea el servicio no corre. Una sola corrida a la vez: un
  /// pedido que llega mientras tanto la repite al terminar.
  Future<void> _reconcileOnlineState() {
    final running = _reconciling;
    if (running != null) {
      _reconcileAgain = true;
      return running;
    }
    final run = () async {
      try {
        do {
          _reconcileAgain = false;
          await _reconcileOnce();
        } while (_reconcileAgain && !_inactive);
      } catch (e) {
        debugPrint('No se pudo reconciliar el estado en línea: $e');
      } finally {
        _reconciling = null;
      }
    }();
    _reconciling = run;
    return run;
  }

  @visibleForTesting
  Future<void> reconcileOnlineStateForTest() => _reconcileOnlineState();

  Future<void> _reconcileOnce() async {
    if (_inactive) return;
    if (!isOnline) {
      _setForegroundPending(false);
      if (await _foregroundService.isRunning) await _foregroundService.stop();
      return;
    }

    final permitted = await _foregroundService.canStart();
    if (!permitted) {
      // Sin permiso el servicio de tipo location no puede seguir.
      if (await _foregroundService.isRunning) await _foregroundService.stop();
      if (_isDelivering) {
        _setForegroundPending(true); // (b)
      } else {
        await _goOfflineWithoutLocation(); // (a)
      }
      return;
    }

    // (c)
    final running =
        await _foregroundService.isRunning || await _startForegroundService();
    // Mientras arrancaba pudo desconectarse (o perder el permiso): un servicio
    // que terminó de arrancar después de la baja no se deja corriendo.
    if (!isOnline || _inactive || !await _foregroundService.canStart()) {
      _setForegroundPending(false);
      if (await _foregroundService.isRunning) await _foregroundService.stop();
      if (isOnline && !_inactive) _reconcileAgain = true;
      return;
    }
    if (running) {
      _setForegroundPending(false);
    } else if (_isDelivering) {
      _setForegroundPending(true);
    } else {
      await _goOfflineWithoutLocation();
    }
  }

  /// Baja completa por falta de permiso y el Inicio vuelve a la pantalla que
  /// lo pide.
  Future<void> _goOfflineWithoutLocation() async {
    debugPrint('Sin permiso de ubicación y sin entrega: se baja al chofer');
    await _rollbackOnline();
    try {
      await _locationService.checkLocationPermission();
    } catch (e) {
      debugPrint('No se pudo revisar el permiso de ubicación: $e');
    }
    hasLocationPermission = false;
    permissionMessage = _locationBlockedMessage();
    notifyListeners();
  }

  String _locationBlockedMessage() {
    if (_locationService.serviceDisabled) {
      return 'El GPS del teléfono está apagado. Encendelo para ponerte en línea.';
    }
    if (_locationService.locationPermission ==
        PermissionOutcome.permanentlyDenied) {
      return 'La ubicación está desactivada para SPLG.\n'
          'Activala desde Ajustes para ponerte en línea y recibir pedidos.';
    }
    return 'Necesitamos tu ubicación para asignarte pedidos cercanos.';
  }

  Future<void> openLocationAlertSettings() =>
      _locationService.openLocationAlertSettings();

  /// Inicializa el ViewModel: pide el permiso de ubicación (con explicación) y
  /// empieza el tracking si se concede.
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _driverSocketService.addListener(_onSocketStateChanged);
    _listenToSocketStreams();
    _startLoadPolling();
    _syncAvailabilityOnOpen();
    await _resolveLocation(interactive: true);
    await refreshNoOrdersReason();
    unawaited(resumeActiveOrder());
    _listenMaintenanceTaps();
    _maintenanceChanges?.cancel();
    _maintenanceChanges = _notifier.changes.listen((_) => notifyListeners());
    unawaited(_notifier.sync());
  }

  /// Al abrir la app el estado en memoria se perdió. Si el chofer tiene un
  /// pedido aceptado o en camino, el back lo tiene en línea y la app lo
  /// reconecta sola (si no, nadie escucharía las ofertas ni los avisos). Si no
  /// tiene ninguno y el back lo conserva «en línea» de una sesión anterior (la
  /// app se cerró sin desconectarse), manda la app, que dice «Desconectado»: se
  /// lo baja, así el despacho no le ofrece pedidos que nadie va a ver. Para
  /// estar en línea hay que tocar «Conectarse».
  Future<void>? _openSync;

  @visibleForTesting
  void syncAvailabilityOnOpenForTest() => _syncAvailabilityOnOpen();

  /// No baja a un chofer en entrega: si tiene un pedido aceptado o en camino
  /// lo conecta (socket, posición, ofertas); si no se pudo averiguar, lo deja.
  void _syncAvailabilityOnOpen() {
    if (isOnline || _connecting || _connectInFlight != null) return;
    final epoch = _sessionEpoch;
    _openSync = () async {
      try {
        if (_trips.activeOrderId != null) {
          if (epoch == _sessionEpoch) {
            unawaited(connect(inDelivery: true, epoch: epoch));
          }
          return;
        }
        final order = await _driverApi.activeOrder();
        if (order != null &&
            (order.status == DriverOrderStatus.accepted ||
                order.status == DriverOrderStatus.onTheWay)) {
          // En entrega el back lo tiene en línea: sin socket no le llegarían
          // las ofertas, los avisos de código ni las cancelaciones.
          if (epoch == _sessionEpoch) {
            unawaited(connect(inDelivery: true, epoch: epoch));
          }
          return;
        }
      } catch (e) {
        debugPrint('No se pudo revisar el pedido en curso al abrir: $e');
        return;
      }
      // Cerró sesión mientras se consultaba: ya se lo bajó el logout.
      if (epoch != _sessionEpoch) return;
      if (isOnline || _connecting || _connectInFlight != null) return;
      await _setAvailability(false);
    }();
  }

  StreamSubscription<void>? _maintenanceOpenedSubscription;

  /// Un push de taller tocado con la app cerrada o en segundo plano abre "Taller".
  void _listenMaintenanceTaps() {
    _maintenanceOpenedSubscription?.cancel();
    _maintenanceOpenedSubscription =
        _fcm.maintenanceOpened.listen((_) => _openTallerIfPending());
    _openTallerIfPending();
  }

  void _openTallerIfPending() {
    if (_fcm.takePendingMaintenance()) {
      unawaited(_notifier.openTaller());
    }
  }

  /// Pregunta al back por qué el chofer no recibe pedidos (`GET
  /// /orders/available`: `message` con `openLoadRequired`). Si falla se
  /// conserva el último estado: un corte de red no prende ni apaga el aviso.
  Future<void> refreshNoOrdersReason() async {
    // Gana la última pregunta: una respuesta lenta de una anterior no pisa a
    // la más nueva.
    final seq = ++_reasonSeq;
    try {
      final reason = await _driverApi.noOrdersReason();
      if (seq != _reasonSeq) return;
      if (noOrdersReason != reason) {
        noOrdersReason = reason;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('No se pudo leer si puede recibir pedidos: $e');
    }
  }

  /// Sólo consulta con la app en primer plano y el Inicio a la vista.
  void _startLoadPolling() {
    _loadTimer?.cancel();
    _loadTimer = Timer.periodic(loadPollInterval, (_) {
      if (!_isHomeVisible()) return;
      unawaited(refreshNoOrdersReason());
      // Respaldo del socket: en línea pero sin conexión (se cayó o venció el
      // token), se renuevan las credenciales y se busca si le asignaron algo.
      if (isOnline && !isConnected) {
        unawaited(_driverSocketService.ensureConnected());
        unawaited(resumeActiveOrder());
      }
    });
  }

  void _stopLoadPolling() {
    _loadTimer?.cancel();
    _loadTimer = null;
  }

  /// Toca el aviso: abre Mi carga y al volver relee.
  Future<void> openMyLoad() async {
    await _navigationService.navigateToMyLoadView();
    await refreshNoOrdersReason();
  }

  void _startSearching() {
    _searchTimer?.cancel();
    search = HomeSearch.searching;
    _searchTimer = Timer(searchTimeout, () {
      if (search == HomeSearch.searching) {
        search = HomeSearch.empty;
        notifyListeners();
      }
    });
  }

  void _stopSearching() {
    _searchTimer?.cancel();
    _searchTimer = null;
    search = HomeSearch.idle;
  }

  /// Al volver de Ajustes se vuelve a mirar el permiso, en silencio (sin
  /// diálogos ni pedidos del sistema). Nunca hay reintentos en bucle.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLoadPolling();
      // El permiso pudo cambiar desde Ajustes sin que Android matara la app:
      // en línea se vuelve a mirar siempre, y se reconcilia.
      if (!hasLocationPermission ||
          _locationService.locationUnavailable ||
          isOnline) {
        _resolveLocation(interactive: false);
      }
      unawaited(_reconcileOnlineState());
      if (_isHomeVisible()) unawaited(refreshNoOrdersReason());
      if (!_inactive) unawaited(resumeActiveOrder());
      // En entrega sin socket (falló al abrir): se reintenta.
      if (_trips.activeOrderId != null && !_manuallyOffline && !_inactive) {
        if (!isConnected) {
          unawaited(connect(inDelivery: true, epoch: _sessionEpoch));
        } else if (!_listeningToSocket || !_onlineSetupDone) {
          unawaited(_completeOnlineSetup());
        }
      }
      unawaited(_notifier.sync());
      if (isOnline) unawaited(syncRouteBatches());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopLoadPolling();
    }
  }

  bool _disposed = false;

  /// Cerrando sesión: nada se reconecta ni se arma hasta terminar.
  bool _loggingOut = false;

  bool get _inactive => _disposed || _loggingOut;

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _loadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _driverSocketService.removeListener(_onSocketStateChanged);
    _retryTimer?.cancel();
    _incomingOrdersSubscription?.cancel();
    _batchSubscription?.cancel();
    _batchClearTimer?.cancel();
    _rejectedSubscription?.cancel();
    _cancelledSubscription?.cancel();
    _routeSheetStartedSubscription?.cancel();
    _maintenanceChanges?.cancel();
    _maintenanceOpenedSubscription?.cancel();
    _locationService.stopTracking();
    mapController.future.then((controller) => controller.dispose());
    super.dispose();
  }

  Future<void> onMapCreated(GoogleMapController controller) async {
    if (!mapController.isCompleted) {
      mapController.complete(controller);
    }
  }

  bool _resolvingLocation = false;

  /// Resuelve el permiso de ubicación: [interactive] muestra la explicación y
  /// el pedido del sistema; en silencio sólo consulta el estado. Una sola
  /// resolución a la vez, y sin reintentos automáticos.
  Future<void> _resolveLocation({required bool interactive}) async {
    if (_resolvingLocation) return;
    _resolvingLocation = true;
    try {
      final hadLocation = hasLocationPermission;
      final granted = interactive
          ? await _locationService.requestLocationPermission()
          : await _locationService.checkLocationPermission();

      // Ya en línea, perder la ubicación no tapa el mapa ni el pedido: queda
      // el aviso. La pantalla de bloqueo es sólo para el arranque sin permiso.
      hasLocationPermission = granted || (hadLocation && isOnline);

      if (granted) {
        permissionMessage = null;
        await _locationService.startTracking();
      } else if (hasLocationPermission) {
        permissionMessage = null;
      } else {
        permissionMessage = _locationBlockedMessage();
      }

      // El permiso pudo cambiar: se ajusta el estado en línea y el servicio.
      await _reconcileOnlineState();
    } catch (e) {
      hasLocationPermission = false;
      permissionMessage = 'No pudimos obtener tu ubicación. Probá de nuevo.';
      debugPrint('Error al resolver el permiso de ubicación: $e');
    } finally {
      _resolvingLocation = false;
      notifyListeners();
    }
  }

  /// Actualiza la ubicación del usuario en el mapa
  void _updateUserLocation(Position position) {
    currentLocation = LatLng(position.latitude, position.longitude);

    // Actualizar o agregar el marcador del usuario
    markers.removeWhere((m) => m.markerId.value == 'user_location');
    markers.add(
      Marker(
        markerId: const MarkerId('user_location'),
        position: currentLocation!,
        infoWindow: const InfoWindow(title: 'Mi ubicación'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
      ),
    );

    // El mapa acompaña al chofer: se centra al abrir y cuando se mueve, salvo
    // que lo esté tocando o lo haya arrastrado hace poco.
    if (_firstFix || !_userIsExploring()) {
      _firstFix = false;
      _animateCameraToPosition(currentLocation!);
    }

    notifyListeners();
  }

  /// Sólo para tests: reemplaza el movimiento real de la cámara.
  @visibleForTesting
  Future<void> Function(LatLng)? cameraMover;

  bool _firstFix = true;
  DateTime? _lastMapTouch;

  /// Cuánto se respeta al usuario después de tocar el mapa antes de volver a
  /// seguirlo.
  static const Duration exploreGrace = Duration(seconds: 20);

  /// El chofer tocó o arrastró el mapa: el seguimiento se frena un rato.
  void onMapTouched() => _lastMapTouch = now();

  bool _userIsExploring() {
    final t = _lastMapTouch;
    return t != null && now().difference(t) < exploreGrace;
  }

  /// Anima la cámara hacia una posición específica
  Future<void> _animateCameraToPosition(LatLng position) async {
    final mover = cameraMover;
    if (mover != null) return mover(position);
    try {
      final controller = await mapController.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: position,
            zoom: 16.0,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error al animar la cámara: $e');
    }
  }

  /// Botón "Solicitar permisos": vuelve a pedir (o lleva a Ajustes si quedó
  /// denegado para siempre).
  Future<void> requestLocationPermission() =>
      _resolveLocation(interactive: true);

  /// Abre la configuración de la app para habilitar permisos
  Future<void> openSettings() async {
    await _permissions.openSettings();
  }

  /// Navega a los Términos y Condiciones de la plataforma (C3).
  Future<void> navigateToTerms() async {
    await _navigationService.navigateToLegalView(
      document: LegalDocument.terms,
    );
  }

  /// Navega a la Política de Privacidad de la plataforma (C3).
  Future<void> navigateToPrivacyPolicy() async {
    await _navigationService.navigateToLegalView(
      document: LegalDocument.privacy,
    );
  }

  /// true desde que el chofer se marca disponible en el backend hasta que se
  /// marca no disponible (independiente de si el socket llegó a conectar).
  bool _markedOnline = false;
  bool _connecting = false;

  /// Un solo estado para la píldora y el botón: si se marcó en línea el botón
  /// dice "Desconectarse" aunque el socket esté reconectando.
  bool get showsDisconnect => isOnline;

  String get statusLabel =>
      !isOnline ? 'Desconectado' : (isConnected ? 'En línea' : 'Reconectando…');

  /// Hay un `connect` en curso (el botón muestra el indicador).
  bool get isConnecting => _connectInFlight != null;

  bool get isOnline => _markedOnline || _driverSocketService.hasSocket;

  /// Cierra sesión y navega a la pantalla de login. Siempre baja al chofer del
  /// radar (`PATCH availability false`, con timeout corto y sin depender del
  /// estado en memoria: tras reabrir la app el estado se perdió pero el back
  /// puede seguir con el chofer disponible). Si había un `connect` en vuelo,
  /// primero se lo hace abortar y se espera a que termine, para que su PATCH
  /// "true" no llegue después del "false".
  Future<void> logout() async {
    setBusy(true);
    _loggingOut = true;
    _sessionEpoch++;
    _manuallyOffline = false;
    _retryTimer?.cancel();
    _endRetryChain();
    try {
      final inFlight = _connectInFlight;
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {}
      }
      await _rollbackOnline();
    } catch (e) {
      debugPrint('Error al bajar al chofer al cerrar sesión: $e');
    }
    // Cada paso va aparte: si uno falla, los demás igual se hacen.
    try {
      // Que no quede un socket ni un envío de posición del chofer anterior.
      _driverSocketService.stopBroadcasting();
    } catch (e) {
      debugPrint('Error al cortar el socket al cerrar sesión: $e');
    }
    try {
      await _locationService.stopTracking();
    } catch (e) {
      debugPrint('Error al detener la ubicación al cerrar sesión: $e');
    }
    try {
      // Cerrar la sesión de verdad: sin esto la app la restaura al reabrir.
      await _driverAuthService.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión: $e');
    } finally {
      // Las claves de idempotencia y el flujo en curso son de la sesión.
      _trips.reset();
      _queuedOrderId = null;
      _assignedWaiting.clear();
      _notifier.reset();
      _fcm.clearPendingMaintenance();
      _board.reset();
      _maintenanceRepo.reset();
      _batches.reset();
      _recovery.reset();
      _clearBatch();
      _loggingOut = false;
      setBusy(false);
    }

    // Navegar a la pantalla de login y limpiar el stack de navegación
    await _navigationService.clearStackAndShow(Routes.loginView);
  }

  /// Se incrementa al cerrar sesión: un `connect` que arrancó con otro valor
  /// aborta y revierte.
  int _sessionEpoch = 0;
  Future<void>? _connectInFlight;

  /// Conecta al chofer para recibir órdenes: lo marca disponible, abre el
  /// socket de choferes, registra su ubicación actual en el GEO y se suscribe
  /// a las ofertas de pedido. Si algo falla después de marcarlo disponible, lo
  /// deja como estaba (no disponible, sin servicio en primer plano ni socket).
  ///
  /// [inDelivery] lo pasa la reconexión automática de quien tiene una entrega
  /// en curso: si falla no se lo baja ni se corta (ver `_connect`). [epoch] es
  /// la sesión con que se decidió conectar; si cambió, se aborta.
  Future<void> connect({bool inDelivery = false, int? epoch}) {
    if (isConnected || _connecting || _connectInFlight != null) {
      debugPrint('connect() ignorado: el chofer ya está conectado');
      return Future.value();
    }
    // Conectarse a mano deja de respetar un «desconectar» anterior.
    if (!inDelivery) _manuallyOffline = false;
    final run = _connect(inDelivery: inDelivery, epoch: epoch);
    _connectInFlight = run;
    notifyListeners();
    return run.whenComplete(() {
      if (identical(_connectInFlight, run)) _connectInFlight = null;
    });
  }

  /// El chofer se desconectó a mano: no se lo reconecta solo al volver a
  /// primer plano, aunque tenga una entrega en curso.
  bool _manuallyOffline = false;

  Future<void> _connect({bool inDelivery = false, int? epoch}) async {
    epoch ??= _sessionEpoch;
    if (epoch != _sessionEpoch || _inactive) return;
    if (isConnected || _connecting) {
      debugPrint('connect() ignorado: el chofer ya está conectado');
      return;
    }

    // Primero las suscripciones: cualquier socket que se abra después (por
    // este connect o por el flujo de una entrega) ya tiene quién lo escuche.
    _listenToSocketStreams();
    final userId = _driverAuthService.userId;
    final token = await _driverAuthService.token;
    if (userId == null || token == null) {
      debugPrint('No se puede conectar: falta la sesión del chofer');
      return;
    }

    // Sin permiso de ubicación no se queda en línea: Android no deja arrancar
    // el servicio en primer plano (tipo location) y, sin él, con la app
    // minimizada el chofer quedaría en el radar sin nadie que escuche. No se
    // lo marca disponible y el Inicio muestra el pedido del permiso. Con una
    // entrega en curso no se corta nada (se avisa con la franja).
    if (inDelivery) _deliveryHold = true;
    if (!_isDelivering && !await _foregroundService.canStart()) {
      debugPrint('connect() sin permiso de ubicación: no se pone en línea');
      await _resolveLocation(interactive: false);
      return;
    }

    _connecting = true;
    try {
      // Que la baja de la apertura no llegue después del alta.
      await _openSync;
      _openSync = null;
      // Marca al chofer DISPONIBLE en el backend (CU-022). Sin esto el backend
      // no sabe formalmente que está en línea, y al desconectar hay que sacarlo
      // del radar (el endpoint hace el ZREM del GEO en el server).
      if (!await _setAvailability(true)) {
        throw StateError('no se pudo marcar disponible');
      }
      _markedOnline = true;
      _abortIfLoggedOut(epoch);

      // Aviso de "estás en línea" (Android 13+ lo oculta sin el permiso de
      // notificaciones). Si se niega, igual se puede trabajar.
      await _permissions.ensure(AppPermission.notifications);
      _abortIfLoggedOut(epoch);

      // Foreground service: mantiene vivo el proceso (socket + GPS) con la app
      // en background. Sin esto, al minimizar la app el chofer se cae del radar.
      // Sin permiso de ubicación no se arranca (Android cerraría la app): lo
      // decide la reconciliación. En entrega se sigue y se avisa; si no, lo
      // bajó y no se abre el socket.
      await _reconcileOnlineState();
      _abortIfLoggedOut(epoch);
      if (!_markedOnline) return;

      _driverSocketService.connect(token, userId);
      if (!await _driverSocketService.waitUntilConnected(_socketTimeout)) {
        throw StateError('el socket no conectó');
      }
      _abortIfLoggedOut(epoch);

      // Posición inicial, recorridos, taller y búsqueda.
      await _completeOnlineSetup(connected: true);
      _abortIfLoggedOut(epoch);
      unawaited(resumeActiveOrder());
    } on _LoggedOutDuringConnect {
      debugPrint('connect() abortado: se cerró la sesión mientras conectaba');
      await _rollbackOnline();
    } catch (e) {
      if (inDelivery || _trips.activeOrderId != null) {
        // En plena entrega no se lo baja ni se corta: el socket reconecta solo
        // o se reintenta al volver a primer plano. Si lo pidió el chofer a mano,
        // se le dice.
        debugPrint('No se pudo conectar el socket en plena entrega: $e');
        if (!inDelivery) {
          await _dialogService.showDialog(
            title: 'No pudimos ponerte en línea',
            description: 'Revisá tu conexión e intentá de nuevo.',
          );
        }
        return;
      }
      debugPrint('No se pudo poner en línea al chofer: $e');
      await _rollbackOnline();
      await _dialogService.showDialog(
        title: 'No pudimos ponerte en línea',
        description: 'Revisá tu conexión e intentá de nuevo.',
      );
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  static const _socketTimeout = Duration(seconds: 8);

  void _abortIfLoggedOut(int? epoch) {
    if (epoch != _sessionEpoch) throw const _LoggedOutDuringConnect();
  }

  /// Deja al chofer fuera de línea sin depender del estado del socket.
  Future<void> _rollbackOnline() async {
    _markedOnline = false;
    _onlineSetupDone = false;
    _foregroundPending = false;
    _deliveryHold = false;
    _stopSearching();
    await _setAvailability(false);
    await _foregroundService.stop();
    _incomingOrdersSubscription?.cancel();
    _incomingOrdersSubscription = null;
    _batchSubscription?.cancel();
    _batchSubscription = null;
    _rejectedSubscription?.cancel();
    _rejectedSubscription = null;
    _cancelledSubscription?.cancel();
    _cancelledSubscription = null;
    _routeSheetStartedSubscription?.cancel();
    _routeSheetStartedSubscription = null;
    _sheetStartPending = false;
    _notifier.stop();
    _board.detach();
    _driverSocketService.disconnect();
  }

  /// Desconecta al chofer: se marca NO DISPONIBLE (el backend lo saca del radar),
  /// deja de recibir ofertas y cierra el socket.
  Future<void> disconnect() async {
    _manuallyOffline = true;
    await _rollbackOnline();
    notifyListeners();
  }

  /// Setea la disponibilidad del chofer en el backend (CU-022).
  /// `PATCH /delivery/user/:userId/availability`. Devuelve si el back lo
  /// aceptó; con un timeout corto para no dejar la pantalla colgada.
  Future<bool> _setAvailability(bool isAvailable) async {
    final token = await _driverAuthService.token;
    final userId = _driverAuthService.userId;
    if (token == null || userId == null) return false;
    try {
      await _apiClient
          .patch(
            'delivery/user/$userId/availability',
            {'available': isAvailable},
            token,
          )
          .timeout(const Duration(seconds: 4));
      return true;
    } catch (e) {
      debugPrint('No se pudo setear disponibilidad ($isAvailable): $e');
      return false;
    }
  }

  StreamSubscription<void>? _rejectedSubscription;
  StreamSubscription<Map<String, dynamic>>? _cancelledSubscription;
  StreamSubscription<void>? _routeSheetStartedSubscription;

  /// El admin inició la hoja de ruta mientras otra retoma consultaba o había una
  /// oferta en pantalla: se vuelve a buscar la parada cuando eso termina, para
  /// que el aviso no se pierda.
  bool _sheetStartPending = false;

  /// `route-sheet:started`: el back ya guardó el inicio; se abre la primera
  /// parada. Sin cobros pendientes (`collect: false`): el aviso es de la hoja.
  void _onRouteSheetStarted() {
    if (_inactive) return;
    if (_resuming || _offerOpen) {
      _sheetStartPending = true;
      return;
    }
    unawaited(resumeActiveOrder(collect: false));
  }

  /// El servidor cortó el socket varias veces seguidas apenas conectar: la
  /// sesión no es válida. Se baja al chofer de línea y se le avisa.
  Future<void> _onSocketRejected() async {
    // Se lee antes de volver a fuera de línea: cerrar el socket lo limpia.
    final revoked = _driverSocketService.accessRevoked;
    _manuallyOffline = true;
    await _rollbackOnline();
    notifyListeners();
    await _dialogService.showDialog(
      title: revoked ? 'Tu cuenta no está habilitada' : 'Se cortó tu conexión',
      description: revoked
          ? 'La distribuidora bloqueó o dio de baja tu cuenta, así que '
              'quedaste fuera de línea. Consultá con tu distribuidora.'
          : 'El servidor cerró la conexión varias veces seguidas, así '
              'que quedaste fuera de línea. Cerrá sesión y volvé a ingresar; si '
              'sigue pasando, consultá con tu distribuidora.',
    );
  }

  /// Lo que completa «estar en línea» una vez que hay socket: suscripciones,
  /// recorridos, taller y posición inicial. Idempotente: lo llaman `_connect` y
  /// el aviso de que el socket reconectó solo.
  bool _onlineSetupDone = false;

  Future<void> _completeOnlineSetup({bool connected = false}) async {
    if (_inactive) return;
    _listenToSocketStreams();
    if (_onlineSetupDone) return;
    final userId = _driverAuthService.userId;
    if (userId == null || !(connected || isConnected)) return;
    _onlineSetupDone = true;
    unawaited(syncRouteBatches());
    _board.bind(userId);
    _board.attach(_driverSocketService.maintenanceEvents);
    _notifier.isBusyWithOrder = () => _trips.activeOrderId != null;
    _notifier.start();
    unawaited(_notifier.sync());
    final position = _locationService.currentPosition ??
        await _locationService.getCurrentLocation();
    if (position != null && (connected || isConnected)) {
      _driverSocketService.sendLocation(
          userId, position.latitude, position.longitude);
    }
    if (!busyWithOrder) _startSearching();
  }

  bool _wasSocketConnected = false;

  /// El servicio del socket cambió: si pasó a conectado (reconectó solo), se
  /// completa lo que `_connect` no llegó a hacer.
  void _onSocketStateChanged() {
    final connected = isConnected;
    if (connected &&
        !_wasSocketConnected &&
        !_manuallyOffline &&
        !_inactive &&
        (_markedOnline || _trips.activeOrderId != null)) {
      unawaited(_completeOnlineSetup());
    }
    if (!connected) _onlineSetupDone = false;
    _wasSocketConnected = connected;
  }

  /// Escucha los avisos del socket (ofertas, cancelaciones, rechazos,
  /// recorridos). Los streams del servicio existen aunque el socket no esté
  /// conectado; se renuevan en cada llamada y se cortan al desconectar.
  void _listenToSocketStreams() {
    _rejectedSubscription ??=
        _driverSocketService.rejected.listen((_) => _onSocketRejected());
    _incomingOrdersSubscription ??=
        _driverSocketService.incomingOrders.listen(_showOrderOfferDialog);
    _cancelledSubscription ??=
        _driverSocketService.orderCancelled.listen(_onQueuedOrderGone);
    _batchSubscription ??=
        _driverSocketService.routeBatchEvents.listen(_onRouteBatchEvent);
    _routeSheetStartedSubscription ??= _driverSocketService.routeSheetStarted
        .listen((_) => _onRouteSheetStarted());
  }

  /// ¿Hay quien escuche las ofertas del socket?
  bool get _listeningToSocket => _incomingOrdersSubscription != null;

  StreamSubscription<void>? _maintenanceChanges;

  /// Hay una propuesta de taller esperando la respuesta del chofer: el Inicio
  /// lo marca aunque esté fuera de línea.
  int get pendingMaintenance => _notifier.pending.length;

  /// Abre "Taller" (sin apilar otra si ya está abierta).
  Future<void> openTaller() => _notifier.openTaller();

  /// Muestra la oferta de pedido por cada aviso que llega
  /// (`server:new-order-request` / `NEW_ORDER` | `NEW_ORDER_RETRY`). Mientras hay
  /// una oferta en pantalla (o un pedido en curso) las demás se ignoran.
  bool _offerOpen = false;

  /// Espera antes de reintentar abrir una entrega que falló al arrancar.
  @visibleForTesting
  Duration flowRetryDelay = const Duration(seconds: 3);

  /// Entrega que falló al arrancar y espera su reintento: cuenta como en curso
  /// para que otra oferta no se mezcle.
  String? _retryingOrderId;
  Timer? _retryTimer;

  /// Reintentos seguidos de abrir una entrega; vuelve a 0 cuando se abre.
  int _flowRetryCount = 0;
  static const _maxFlowRetries = 3;

  /// Hay un reintento programado (lo marca [_scheduleFlowRetry]).
  bool _retryScheduled = false;

  void _scheduleFlowRetry(int epoch, {bool consume = true}) {
    _retryTimer?.cancel();
    if (consume && ++_flowRetryCount > _maxFlowRetries) {
      _endRetryChain();
      unawaited(_dialogService.showDialog(
        title: 'No pudimos abrir tu entrega',
        description:
            'Tenés un pedido en curso que no se pudo abrir. Reabrí la app o '
            'consultá con tu distribuidora.',
      ));
      return;
    }
    _retryScheduled = true;
    _retryTimer = Timer(flowRetryDelay, () async {
      _retryScheduled = false;
      if (epoch != _sessionEpoch || _disposed) {
        _endRetryChain();
        return;
      }
      // Si hay una oferta o un anuncio en pantalla, la retoma espera su turno
      // sin gastar un intento.
      if (_offerOpen || _startingOrderId != null) {
        _scheduleFlowRetry(epoch, consume: false);
        return;
      }
      await resumeActiveOrder(collect: false, retry: true);
      // Si la retoma no reprogramó, la cadena terminó (bien o mal).
      if (!_retryScheduled) _endRetryChain();
    });
  }

  void _endRetryChain() {
    _flowRetryCount = 0;
    _retryingOrderId = null;
    _retryScheduled = false;
  }

  /// Pedido en espera que se está anunciando antes de abrir su entrega: hasta
  /// que arranca cuenta como en curso, para que otra oferta no abra un segundo flujo.
  String? _startingOrderId;

  /// Hay una oferta abierta o un pedido en curso.
  @visibleForTesting
  bool get busyWithOrder =>
      _offerOpen ||
      _startingOrderId != null ||
      _retryingOrderId != null ||
      _trips.activeOrderId != null ||
      _batchQueue.isNotEmpty;

  /// Pedido ya aceptado que espera a que termine la entrega en curso (CU-013):
  /// el chofer por terminar puede tomar UNO más, nunca dos encolados.
  String? _queuedOrderId;

  @visibleForTesting
  String? get queuedOrderId => _queuedOrderId;

  /// Con la entrega en curso EN CAMINO y nada más en espera, la oferta que
  /// llega se muestra: el despacho sólo la manda si el chofer está por terminar.
  /// Cualquier otro caso (pedido recién aceptado, oferta abierta, recorrido) la
  /// rechaza como siempre. Si no se puede averiguar, no se encola.
  Future<bool> _canQueueOffer() async {
    if (_startingOrderId != null ||
        _retryingOrderId != null ||
        _trips.activeOrderId == null ||
        _queuedOrderId != null ||
        _batchQueue.isNotEmpty) {
      return false;
    }
    try {
      final current = await _driverApi.activeOrder();
      // Si mientras tanto arrancó el anuncio de otro pedido, no hay lugar.
      if (_startingOrderId != null || _retryingOrderId != null) return false;
      return current?.status == DriverOrderStatus.onTheWay;
    } catch (e) {
      debugPrint('No se pudo revisar el pedido en curso para la oferta: $e');
      return false;
    }
  }

  Future<void> _showOrderOfferDialog(Map<String, dynamic> offer,
      {bool reshown = false}) async {
    final orderId = offer['orderId']?.toString();
    if (orderId == null) {
      debugPrint('Oferta de pedido sin orderId, se ignora: $offer');
      return;
    }
    // Un pedido de un recorrido que el chofer aceptó llega por el mismo evento
    // que una oferta, pero ya es suyo: no hay nada que ofrecer.
    if (_batchOrderIds.remove(orderId)) {
      debugPrint('Pedido $orderId del recorrido: ya está asignado');
      return;
    }
    // La distribuidora lo asignó a mano (`assigned: true`): ya es de este
    // chofer. No es una oferta: nunca se muestra con cuenta regresiva ni se
    // rechaza.
    if (offer['assigned'] == true) {
      await _onAssigned(orderId);
      return;
    }
    // Mientras se busca un pedido para retomar, la oferta espera la decisión:
    // si no, el diálogo y la pantalla del pedido retomado se pisarían.
    final deciding = _resumeDecision;
    if (_resuming && deciding != null) await deciding.future;
    final busy = busyWithOrder;
    var toQueue = false;
    if (!busy) {
      _offerOpen = true;
    } else if (!_offerOpen) {
      // Una oferta a la vez: se reserva antes de consultar al back, para que
      // otra que llega casi junta se rechace por ocupado.
      _offerOpen = true;
      toQueue = await _canQueueOffer();
      if (!toQueue) {
        // Se libera como lo haría el cierre de una oferta: si la entrega en
        // curso terminó mientras se esperaba, la retoma se programa igual.
        _offerOpen = false;
        final done = _justFinished;
        _justFinished = null;
        if (done != null) _resumeSoon(done);
      }
    }
    if (!_offerOpen || (busy && !toQueue)) {
      // Ocupado: se rechaza explícitamente para que el back la pase a otro
      // chofer enseguida, en vez de esperar a que venza.
      debugPrint('Oferta $orderId rechazada: ya hay un pedido en pantalla');
      await rejectOrder(orderId);
      return;
    }
    var reshow = false;
    Future<void> Function()? startFlow;
    // La oferta tiene prioridad: un aviso de taller abierto se cierra y vuelve después.
    _notifier.offerStarted();
    try {
      // Con el QR de entrega arriba, la oferta va en una banda que no lo tapa.
      final response = await _offerSlot.show(
        offer,
        () => _dialogService.showCustomDialog(
          variant: DialogType.orderOffer,
          data: offer,
          barrierDismissible: false,
        ),
      );

      if (response?.confirmed == true) {
        final data = response?.data;
        final map = data is Map
            ? MapApp.values.firstWhere((m) => m.name == data['map'],
                orElse: () => MapApp.stay)
            : MapApp.stay;
        final lat = data is Map ? (data['lat'] as num?)?.toDouble() : null;
        final lng = data is Map ? (data['lng'] as num?)?.toDouble() : null;
        final alreadyAccepted = data is Map && data['accepted'] == true;
        if (data is Map && data['refused'] == true) {
          // El back ya contestó que no: se dice y no se reintenta con otra clave.
          await _dialogService.showDialog(
            title: 'No pudimos aceptar el pedido',
            description:
                data['error']?.toString() ?? 'El pedido ya no está disponible.',
          );
          if (isOnline) {
            _startSearching();
            notifyListeners();
          }
          return;
        }
        if (toQueue) {
          await _queueOrder(orderId, alreadyAccepted: alreadyAccepted);
        } else {
          // La entrega dura mucho más que la oferta: se decide acá, se libera
          // la oferta y el flujo arranca después (si no, durante toda la
          // entrega se rechazaría cualquier oferta nueva).
          final session = await _confirmAccept(orderId, alreadyAccepted);
          if (session != null) {
            startFlow = () => _runOrderFlow(orderId,
                token: session.$1,
                userId: session.$2,
                map: map,
                lat: lat,
                lng: lng);
          }
        }
      } else if (response == null && toQueue) {
        // Al terminar la entrega en curso la navegación cerró el diálogo: no
        // fue una decisión del chofer, así que no se rechaza sola.
        final vigente = await _recoverDismissedOffer(orderId, offer);
        reshow = vigente && !reshown;
      } else {
        await rejectOrder(orderId);
        if (isOnline) {
          _startSearching();
          notifyListeners();
        }
      }
    } catch (e) {
      // Un fallo al mostrar la oferta no la deja colgada: se rechaza para que
      // el back la pase a otro chofer.
      debugPrint('Error con la oferta $orderId: $e');
      await rejectOrder(orderId);
    } finally {
      _offerOpen = false;
      final done = _justFinished;
      _justFinished = null;
      // Si va a retomarse un pedido asignado, los avisos esperan a que termine.
      // Si arranca la entrega, los avisos esperan a que termine (`_resumeSoon`).
      _notifier.offerEnded(pump: done == null && startFlow == null);
      if (done != null) {
        _resumeSoon(done);
      } else if (startFlow == null &&
          (_assignedWaiting.isNotEmpty || _sheetStartPending)) {
        // Llegó una asignación (o el inicio de la hoja de ruta) con la oferta
        // en pantalla: ahora que se cerró sin abrir otra entrega, se abre.
        _sheetStartPending = false;
        _resumeSoon('');
      }
    }
    if (reshow) unawaited(_showOrderOfferDialog(offer, reshown: true));
    if (startFlow != null) {
      try {
        await startFlow();
      } catch (e) {
        // El pedido ya está aceptado: no se rechaza. Se suelta el flujo, se
        // vuelve a buscar y se programa la retoma (`resumeActiveOrder`).
        debugPrint('No se pudo abrir la entrega de $orderId: $e');
        _trips.endFlow();
        // El pedido sigue aceptado en el back: se vuelve a intentar retomarlo.
        _retryingOrderId = orderId;
        _scheduleFlowRetry(_sessionEpoch);
        if (isOnline) {
          _startSearching();
          notifyListeners();
        }
      }
    }
  }

  /// Pedidos asignados a mano que llegaron con el chofer ocupado (oferta en
  /// pantalla, entrega en curso con otro ya en espera, otra entrega abriéndose).
  /// Siguen siendo suyos en el back: se abren con la retoma cuando quede libre.
  /// También reservan el id para que un aviso repetido no abra dos entregas.
  final List<String> _assignedWaiting = [];

  @visibleForTesting
  List<String> get assignedWaiting => List.unmodifiable(_assignedWaiting);

  /// El pedido ya está abierto, abriéndose, en espera o anotado.
  bool _assignmentKnown(String id) =>
      _trips.activeOrderId == id ||
      _queuedOrderId == id ||
      _startingOrderId == id ||
      _retryingOrderId == id ||
      _assignedWaiting.contains(id);

  /// Asignación manual (`server:new-order-request` con `assigned: true`). La
  /// reserva del id es sincrónica, antes de cualquier await: un aviso repetido
  /// (o el aviso más la retoma al reconectar) no abre dos entregas.
  Future<void> _onAssigned(String orderId) async {
    if (_assignmentKnown(orderId)) {
      debugPrint('Pedido asignado $orderId: ya se está atendiendo');
      return;
    }
    final deciding = _resumeDecision;
    if (_resuming && deciding != null && !deciding.isCompleted) {
      // Se está buscando un pedido para retomar: queda anotado (reservado) y
      // se decide cuando la retoma decidió. Si la retoma lo abrió, ya está.
      // (Ya decidida, la retoma sigue `_resuming` mientras dura la entrega que
      // abrió: eso es estar ocupado, no esperar.)
      _assignedWaiting.add(orderId);
      await deciding.future;
      if (!_assignedWaiting.remove(orderId)) return;
      return _onAssigned(orderId);
    }
    if (!busyWithOrder) {
      // Libre: se abre la entrega.
      _startingOrderId = orderId;
      debugPrint('Pedido $orderId asignado por la distribuidora');
      await _openAssigned(orderId);
      return;
    }
    if (_trips.activeOrderId != null &&
        _queuedOrderId == null &&
        !_offerOpen &&
        _startingOrderId == null &&
        _retryingOrderId == null) {
      // Con una entrega en curso queda como el próximo (CU-013).
      _queuedOrderId = orderId;
      // Con el QR de entrega arriba el aviso va en esa pantalla, sin taparlo.
      if (_offerSlot.announce('Te asignaron un pedido más: te lo mostramos '
          'apenas termines esta entrega.')) {
        return;
      }
      await _dialogService.showDialog(
        title: 'Tu próximo pedido',
        description: 'Te asignaron un pedido más. Terminá la entrega que '
            'llevás: apenas la confirmes te lo mostramos para que salgas.',
      );
      return;
    }
    // Ocupado de otra forma: no se pierde, se abre al quedar libre.
    _assignedWaiting.add(orderId);
    debugPrint('Pedido asignado $orderId en espera: el chofer está ocupado');
  }

  Future<void> _openAssigned(String orderId) async {
    final epoch = _sessionEpoch;
    try {
      final session = await _confirmAccept(orderId, true);
      if (session == null || epoch != _sessionEpoch || _disposed) {
        _startingOrderId = null;
        return;
      }
      // Sin await entre soltar la reserva y marcar el pedido activo
      // (primera línea de `_runOrderFlow`).
      _startingOrderId = null;
      await _runOrderFlow(orderId, token: session.$1, userId: session.$2);
    } catch (e) {
      // Sigue asignado en el back: se suelta el flujo y se reintenta retomarlo.
      debugPrint('No se pudo abrir la entrega asignada $orderId: $e');
      _startingOrderId = null;
      _trips.endFlow();
      _retryingOrderId = orderId;
      _scheduleFlowRetry(_sessionEpoch);
    }
  }

  /// El diálogo de una oferta en espera se cerró sin respuesta. Si el pedido ya
  /// quedó aceptado por este chofer, pasa a ser el que espera; si la oferta
  /// sigue vigente, devuelve true para mostrarla de nuevo; si no, no hay nada
  /// que hacer (el despacho la vence).
  Future<bool> _recoverDismissedOffer(
      String orderId, Map<String, dynamic> offer) async {
    try {
      final o = await _trips.order(orderId);
      final mine = (await _driverApi.profile()).deliveryId;
      if (o.status == DriverOrderStatus.accepted &&
          o.deliveryId != null &&
          o.deliveryId == mine) {
        _queuedOrderId = orderId;
        return false;
      }
      final expires = DateTime.tryParse(offer['expiresAt']?.toString() ?? '');
      return o.status == DriverOrderStatus.pending &&
          expires != null &&
          expires.isAfter(now());
    } catch (e) {
      debugPrint('No se pudo revisar la oferta $orderId: $e');
      return false;
    }
  }

  /// El pedido en espera se canceló, se liberó o se reasignó (`order:cancelled`
  /// llega por los tres): deja de esperar y el chofer puede recibir otra oferta.
  void _onQueuedOrderGone(Map<String, dynamic> payload) {
    final id = payload['orderId']?.toString();
    if (id != null) _assignedWaiting.remove(id);
    if (id == null || id != _queuedOrderId) return;
    _queuedOrderId = null;
    debugPrint('El pedido en espera $id ya no es del chofer');
    unawaited(_dialogService.showDialog(
      title: 'Tu próximo pedido',
      description: 'Tu próximo pedido ya no está asignado a vos.',
    ));
  }

  /// Acepta un pedido que llegó con otra entrega en curso: queda en espera y
  /// se retoma al terminar la actual (`resumeActiveOrder`). No abre pantalla,
  /// ni mapa, ni cambia el tracking de la entrega que sigue en curso.
  Future<void> _queueOrder(String orderId,
      {required bool alreadyAccepted}) async {
    if (!alreadyAccepted && !await _acceptWithConfirmation(orderId)) return;
    _queuedOrderId = orderId;
    debugPrint('Pedido $orderId aceptado en espera');
    // Con el QR de entrega arriba el aviso va en esa pantalla, sin taparlo.
    if (_offerSlot.announce('Aceptaste un pedido más: te lo mostramos '
        'apenas termines esta entrega.')) {
      return;
    }
    await _dialogService.showDialog(
      title: 'Tu próximo pedido',
      description: 'Aceptaste un pedido más. Terminá la entrega que llevás: '
          'apenas la confirmes te lo mostramos para que salgas.',
    );
  }

  /// Rechaza una oferta (CU-016): `POST /orders/:orderId/reject`. El backend
  /// cierra la oferta y re-ofrece al siguiente chofer de inmediato. Best-effort.
  Future<void> rejectOrder(String orderId) async {
    // La distribuidora se lo asignó mientras la oferta estaba en pantalla: ya
    // es suyo y no se rechaza.
    if (_assignmentKnown(orderId)) {
      debugPrint('Pedido $orderId asignado: la oferta no se rechaza');
      return;
    }
    try {
      await _trips.reject(orderId);
      debugPrint('Oferta $orderId rechazada por el chofer');
    } catch (e) {
      debugPrint('Error rechazando la oferta $orderId: $e');
    }
  }

  /// Acepta un pedido ofertado: `PATCH /orders/:orderId/status {accepted}`
  /// (idempotente; con [alreadyAccepted] el diálogo de la oferta ya lo hizo).
  /// Si el back lo confirma, arranca el tracking de la entrega, abre el mapa
  /// elegido y va a la pantalla del pedido; si lo rechaza (la oferta venció o
  /// la tomó otro chofer) lo dice y vuelve a buscar.
  Future<void> acceptOrder(
    String orderId, {
    MapApp map = MapApp.stay,
    double? lat,
    double? lng,
    bool alreadyAccepted = false,
  }) async {
    final session = await _confirmAccept(orderId, alreadyAccepted);
    if (session == null) return;
    await _runOrderFlow(orderId,
        token: session.$1, userId: session.$2, map: map, lat: lat, lng: lng);
  }

  /// Deja el pedido aceptado en el back (sin abrir su flujo). Devuelve el
  /// token y el usuario con que seguir, o null si no se pudo.
  Future<(String, String)?> _confirmAccept(
      String orderId, bool alreadyAccepted) async {
    final token = await _driverAuthService.token;
    final userId = _driverAuthService.userId;
    if (token == null || userId == null) {
      debugPrint('No se puede aceptar el pedido $orderId: falta la sesión');
      return null;
    }

    // La oferta ya lo aceptó en el back (antes de elegir mapa): no se repite.
    if (!alreadyAccepted && !await _acceptWithConfirmation(orderId)) {
      if (isOnline) {
        _startSearching();
        notifyListeners();
      }
      return null;
    }
    debugPrint('Pedido $orderId aceptado');
    return (token, userId);
  }

  /// `PATCH accepted`. Con la red caída o un timeout no se sabe si el back lo
  /// aplicó: se consulta el pedido y, si quedó aceptado por este chofer, se
  /// sigue; si no, se reintenta una vez con la MISMA Idempotency-Key y recién
  /// ahí se descarta. Un rechazo del back (400/403/409) se dice y no se insiste.
  Future<bool> _acceptWithConfirmation(String orderId) async {
    Object? failure;
    try {
      await _trips.setStatus(orderId, 'accepted');
      return true;
    } catch (e) {
      failure = e;
    }
    if (failure is DioException && failure.response == null) {
      debugPrint('Aceptar $orderId sin respuesta ($failure): se verifica');
      try {
        final o = await _trips.order(orderId);
        final mine = (await _driverApi.profile()).deliveryId;
        if (o.status == DriverOrderStatus.accepted &&
            o.deliveryId != null &&
            o.deliveryId == mine) {
          return true;
        }
      } catch (e) {
        debugPrint('No se pudo verificar el pedido $orderId: $e');
      }
      try {
        await _trips.setStatus(orderId, 'accepted'); // misma clave
        return true;
      } catch (e) {
        failure = e;
      }
    }
    debugPrint('Error aceptando el pedido $orderId: $failure');
    await _dialogService.showDialog(
      title: 'No pudimos aceptar el pedido',
      description: DriverApiService.errorMessage(failure),
    );
    return false;
  }

  /// Del pedido aceptado hasta el fin REAL del flujo (completado, cancelado o
  /// liberado): el Inicio no retoma cuando una pantalla reemplaza a otra.
  Future<void> _runOrderFlow(
    String orderId, {
    required String token,
    required String userId,
    MapApp map = MapApp.stay,
    double? lat,
    double? lng,
  }) async {
    // Si el flujo termina en el cobro y el chofer toca "Más tarde", no se le
    // reabre solo al volver de segundo plano.
    _promptedPayments.add(orderId);
    _trips.beginFlow(orderId);
    _stopSearching();
    // El socket que abre la entrega tiene que tener quién escuche las ofertas.
    _listenToSocketStreams();
    _driverSocketService.startBroadcasting(orderId, userId, token);
    await _foregroundService.update(
      title: 'En reparto',
      text: 'Entrega en curso',
    );
    if (map != MapApp.stay && lat != null && lng != null) {
      unawaited(NavigationLauncher.open(map, lat, lng));
    }
    await _navigationService.navigateToDeliveryView(orderId: orderId);
    // Abrió: termina la cadena de reintentos.
    _flowRetryCount = 0;
    _retryingOrderId = null;
    // Desde acá la entrega ya arrancó: un error al cerrarla no la reintenta.
    try {
      await _trips.waitFlow();
      await _afterFlow(orderId);
    } catch (e) {
      debugPrint('Error al cerrar la entrega $orderId: $e');
    }
  }

  /// Pedido entregado en efectivo y sin cobrar (la app se cerró en medio del
  /// cobro): se retoma directo en la pantalla de cobro.
  Future<void> _runPaymentFlow(String orderId) async {
    // Una sola vez por sesión: si lo deja para después ("Más tarde"), no se
    // le vuelve a abrir solo.
    _promptedPayments.add(orderId);
    _trips.beginFlow(orderId);
    _stopSearching();
    try {
      await _navigationService.navigateToPaymentView(orderId: orderId);
    } catch (e) {
      // No se abrió el cobro: no se deja el pedido activo pegado.
      _trips.endFlow();
      rethrow;
    }
    try {
      await _trips.waitFlow();
      await _afterFlow(orderId);
    } catch (e) {
      debugPrint('Error al cerrar el cobro $orderId: $e');
    }
  }

  /// Pedido que terminó su flujo hace un instante: el reintento de retomar
  /// lo saltea para no volver a abrir el mismo si quedó sin terminar.
  String? _justFinished;

  /// Cobros que ya se le abrieron al chofer en esta sesión.
  final Set<String> _promptedPayments = {};

  @visibleForTesting
  Future<void> afterFlowForTest(String orderId) => _afterFlow(orderId);

  Future<void> _afterFlow(String orderId) async {
    // Dentro de un recorrido sigue la próxima parada, en el orden del lote.
    if (_batchQueue.isNotEmpty && !_offerOpen) {
      if (await _openNextBatchStop()) return;
    }
    await _foregroundService.update(
      title: 'Estás en línea',
      text: 'Recibiendo pedidos cercanos',
    );
    // Terminó la entrega: sin permiso de ubicación ya no hay qué sostener y
    // se lo baja; con permiso, el servicio sigue (o arranca si faltaba).
    _deliveryHold = false;
    await _reconcileOnlineState();
    // Una entrega que reabrió el socket por su cuenta completa el armado.
    if (isOnline && !_onlineSetupDone && !_manuallyOffline) {
      await _completeOnlineSetup();
    }
    if (isOnline) _startSearching();
    notifyListeners();
    // Si el admin le asignó otro pedido mientras tanto, la oferta se rechazó
    // por estar ocupado: ahora que quedó libre, el pedido asignado aparece.
    // (Dentro de una oferta lo hace el cierre de `_showOrderOfferDialog`.)
    if (_offerOpen) {
      _justFinished = orderId;
    } else {
      _resumeSoon(orderId);
    }
  }

  /// Después de que termine la llamada que está retomando (su bandera
  /// `_resuming` sigue arriba hasta entonces).
  void _resumeSoon(String except) {
    final notifier = _notifier;
    final epoch = _sessionEpoch;
    unawaited(Future<void>.delayed(
        Duration.zero,
        () => (epoch != _sessionEpoch || _disposed
                ? Future<void>.value()
                : resumeActiveOrder(except: except, collect: false))
            // Terminado el pedido (y el que se haya retomado): los avisos de
            // taller que esperaban pueden salir.
            .whenComplete(notifier.recheck)));
  }

  // --- Recorridos (CU-107, M4) ---------------------------------------------

  StreamSubscription<RouteBatchEvent>? _batchSubscription;

  /// Lote cuya oferta está en pantalla.
  String? _batchOpenId;
  final Set<String> _batchFetching = {};

  /// Pedidos del recorrido ofrecido o aceptado: el back los manda por
  /// `server:new-order-request` al asignarlos y no son ofertas.
  final Set<String> _batchOrderIds = {};
  Timer? _batchClearTimer;

  /// Pedidos del recorrido aceptado que faltan, en el orden de las paradas.
  final List<String> _batchQueue = [];

  @visibleForTesting
  List<String> get batchQueue => List.unmodifiable(_batchQueue);

  void _clearBatch() {
    _batchClearTimer?.cancel();
    _batchOrderIds.clear();
    _batchQueue.clear();
  }

  void _onRouteBatchEvent(RouteBatchEvent e) {
    // El cierre lo atiende la propia pantalla de la oferta.
    if (e is RouteBatchOffered) {
      unawaited(offerRouteBatch(e.batchId, rejectIfBusy: true));
    }
  }

  /// Oferta de recorrido (`route-batch:offer`): se lee el lote y se abre la
  /// pantalla. Con un pedido en pantalla o en curso se rechaza (con [rejectIfBusy])
  /// para que el despacho lo pase enseguida a otro chofer.
  @visibleForTesting
  Future<void> offerRouteBatch(String batchId,
      {required bool rejectIfBusy}) async {
    if (_batchOpenId == batchId || !_batchFetching.add(batchId)) return;
    try {
      final deciding = _resumeDecision;
      if (_resuming && deciding != null) await deciding.future;
      if (busyWithOrder) {
        if (rejectIfBusy) {
          debugPrint(
              'Recorrido $batchId rechazado: ya hay un pedido en pantalla');
          await _rejectBatch(batchId);
        }
        return;
      }
      final RouteBatch batch;
      try {
        batch = await _batches.batch(batchId);
      } catch (e) {
        debugPrint('No se pudo leer el recorrido $batchId: $e');
        return;
      }
      await _showRouteBatchDialog(batch);
    } finally {
      _batchFetching.remove(batchId);
    }
  }

  /// Al ponerse en línea y al volver a primer plano: si el despacho dejó un
  /// recorrido esperando respuesta (push, socket caído), se muestra.
  @visibleForTesting
  Future<void> syncRouteBatches() async {
    try {
      final list = await _batches.mine();
      final now = DateTime.now();
      for (final b in list) {
        if (b.awaitsAnswer && b.offer!.remaining(now) > Duration.zero) {
          await offerRouteBatch(b.batchId, rejectIfBusy: false);
          return;
        }
      }
    } catch (e) {
      debugPrint('No se pudieron leer los recorridos: $e');
    }
  }

  Future<void> _rejectBatch(String batchId) async {
    try {
      await _batches.reject(batchId);
    } catch (e) {
      debugPrint('Error rechazando el recorrido $batchId: $e');
    }
  }

  Future<void> _showRouteBatchDialog(RouteBatch batch) async {
    if (busyWithOrder || !batch.awaitsAnswer) return;
    _offerOpen = true;
    _batchOpenId = batch.batchId;
    _batchClearTimer?.cancel();
    _batchOrderIds
      ..clear()
      ..addAll(batch.stops.map((s) => s.orderId));
    // Igual que una oferta suelta: un aviso de taller abierto se cierra.
    _notifier.offerStarted();
    var accepted = false;
    try {
      final response = await _dialogService.showCustomDialog(
        variant: DialogType.routeBatchOffer,
        data: batch,
        barrierDismissible: false,
      );
      final data = response?.data;
      final outcome = data is Map ? data['outcome'] : null;
      switch (outcome) {
        case BatchOutcome.accepted:
          accepted = true;
        case BatchOutcome.refused:
          await _dialogService.showDialog(
            title: 'No pudimos aceptar el recorrido',
            description: data is Map && data['error'] != null
                ? data['error'].toString()
                : 'El recorrido ya no está disponible.',
          );
        case BatchOutcome.expired || BatchOutcome.closed:
          break; // el back ya cerró la oferta
        case BatchOutcome.rejected || null:
          await _rejectBatch(batch.batchId);
      }
    } catch (e) {
      debugPrint('Error con el recorrido ${batch.batchId}: $e');
      await _rejectBatch(batch.batchId);
    } finally {
      _offerOpen = false;
      _batchOpenId = null;
      if (accepted) {
        _batchQueue
          ..clear()
          ..addAll(batch.stops.map((s) => s.orderId));
        // Lo que no llegó por el socket en un rato ya no va a llegar.
        _batchClearTimer =
            Timer(const Duration(minutes: 2), _batchOrderIds.clear);
      } else {
        _batchOrderIds.clear();
      }
      _notifier.offerEnded(pump: !accepted);
      if (accepted) {
        unawaited(_startBatch());
      } else if (isOnline) {
        _startSearching();
        notifyListeners();
      }
      if (!accepted && _sheetStartPending) _resumeSoon('');
    }
  }

  Future<void> _startBatch() async {
    if (await _openNextBatchStop()) return;
    _resumeSoon('');
  }

  /// Abre la próxima parada del recorrido que siga siendo del chofer. `false`
  /// si no queda ninguna. Las paradas que salieron (cancelada, asignada aparte)
  /// se saltean.
  Future<bool> _openNextBatchStop() async {
    final token = await _driverAuthService.token;
    final userId = _driverAuthService.userId;
    while (_batchQueue.isNotEmpty) {
      if (token == null || userId == null) break;
      final id = _batchQueue.first;
      DriverOrderStatus? status;
      try {
        status = (await _trips.order(id)).status;
      } catch (e) {
        debugPrint('Parada $id del recorrido no disponible: $e');
      }
      if (_batchQueue.isEmpty || _batchQueue.first != id) return false;
      _batchQueue.removeAt(0);
      if (status == DriverOrderStatus.accepted ||
          status == DriverOrderStatus.onTheWay) {
        await _runOrderFlow(id, token: token, userId: userId);
        return true;
      }
    }
    _batchQueue.clear();
    return false;
  }

  bool _resuming = false;

  /// Se completa cuando `resumeActiveOrder` decidió qué hacer (retomar algo o
  /// nada), antes de abrir la pantalla.
  Completer<void>? _resumeDecision;

  /// Si el chofer tiene un pedido `accepted` u `on_the_way` (porque mató la app,
  /// se cayó o volvió del background), lo retoma abriendo la pantalla del
  /// pedido. Lo pregunta a `GET /orders/delivery/me/active` (sin importar cuándo
  /// se creó). Se llama al abrir, al conectarse y al volver a primer plano.
  ///
  /// [collect] además retoma el cobro de la jornada: SÓLO el último pedido que
  /// el chofer entregó hoy en efectivo y sigue sin cobrar (nunca en cadena, ni
  /// los de días anteriores, que quedan en "Cobros pendientes").
  Future<void> resumeActiveOrder({
    String? except,
    bool collect = true,
    bool retry = false,
  }) async {
    if (_inactive) return;
    if (_resuming || _offerOpen || _trips.activeOrderId != null) return;
    _resuming = true;
    // Esta retoma atiende el inicio de hoja que estuviera anotado.
    _sheetStartPending = false;
    final decision = _resumeDecision = Completer<void>();
    final epoch = _sessionEpoch;
    String? openingOrderId;
    final waitingBefore = [..._assignedWaiting];
    try {
      final token = await _driverAuthService.token;
      final userId = _driverAuthService.userId;
      if (token == null || userId == null || _inactive) return;
      final queuedId = _queuedOrderId;
      // La marca se conserva si la consulta falla: se limpia recién con la respuesta.
      final order = await _driverApi.activeOrder();
      // Cerró sesión mientras se consultaba: no se abre nada.
      if (epoch != _sessionEpoch || _inactive) return;
      _queuedOrderId = null;
      // Sin pedido en curso en el back, las asignaciones anotadas antes de la
      // consulta ya no son del chofer (canceladas o reasignadas).
      if (order == null) _assignedWaiting.removeWhere(waitingBefore.contains);
      final assignedNow = order != null && _assignedWaiting.contains(order.id);
      DriverOrder? current;
      DriverOrder? toCollect;
      if (order != null && order.id != except) {
        if (order.status == DriverOrderStatus.accepted ||
            order.status == DriverOrderStatus.onTheWay) {
          current = order;
        } else if (collect && _isTodaysPendingCollection(order)) {
          toCollect = order;
        }
      }
      // Una asignación anotada que el back ya no da como en curso, no espera más.
      if (assignedNow && current == null) _assignedWaiting.remove(order.id);
      // El back no tiene entrega en curso: la marca de la reconexión se suelta.
      if (current == null && _deliveryHold && _trips.activeOrderId == null) {
        _deliveryHold = false;
        unawaited(_reconcileOnlineState());
      }
      if (_offerOpen || _trips.activeOrderId != null) return;
      if (current != null) {
        debugPrint('Retomando el pedido en curso ${current.id}');
        _assignedWaiting.remove(current.id);
        // La oferta que espera se reanuda en un microtask, cuando el flujo ya
        // marcó el pedido como activo (primera línea de `_runOrderFlow`).
        decision.complete();
        if (current.id == queuedId || assignedNow) {
          _startingOrderId = current.id;
          _trips.beginFlow(current.id);
          try {
            await _announceNext(current, assigned: assignedNow);
          } catch (e) {
            debugPrint('No se pudo anunciar el próximo pedido: $e');
          } finally {
            _startingOrderId = null;
          }
          if (epoch != _sessionEpoch || _inactive) {
            _trips.endFlow();
            return;
          }
        }
        openingOrderId = current.id;
        await _runOrderFlow(current.id, token: token, userId: userId);
      } else if (toCollect != null) {
        debugPrint('Retomando el cobro del pedido ${toCollect.id}');
        decision.complete();
        await _runPaymentFlow(toCollect.id);
      }
    } catch (e) {
      debugPrint('No se pudo buscar un pedido en curso: $e');
      // Si falló al abrir la entrega, no se deja el pedido activo pegado.
      final failed = openingOrderId;
      if (failed != null) _trips.endFlow();
      // Si ya venía reintentando, cualquier error (también de red al consultar)
      // reprograma mientras queden intentos.
      if (failed != null || retry) {
        _retryingOrderId = failed ?? _retryingOrderId;
        _scheduleFlowRetry(epoch);
      }
    } finally {
      _resuming = false;
      if (!decision.isCompleted) decision.complete();
      // Si el admin inició la hoja mientras se consultaba, la marca sigue
      // prendida hasta que otra retoma la atienda (no se pierde si una oferta
      // se cruza antes).
      final sheetStarted = _sheetStartPending;
      // Una asignación que llegó mientras se consultaba (y no vino en la
      // respuesta) se busca otra vez; las anteriores ya las contestó el back.
      // Lo mismo si en ese lapso el admin inició la hoja de ruta.
      if (epoch == _sessionEpoch &&
          !_inactive &&
          _trips.activeOrderId == null &&
          (sheetStarted ||
              _assignedWaiting.any((id) => !waitingBefore.contains(id)))) {
        _resumeSoon('');
      }
    }
  }

  /// El pedido que el chofer había aceptado en espera pasa a ser el actual.
  Future<void> _announceNext(DriverOrder next, {bool assigned = false}) {
    final who = [next.customerName, next.address]
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .join(' · ');
    final what = assigned
        ? 'el pedido que te asignó la distribuidora'
        : 'el pedido que aceptaste';
    return _dialogService.showDialog(
      title: 'Tu próximo pedido',
      description: who.isEmpty
          ? 'Ya podés salir con $what.'
          : 'Ya podés salir con $what: $who.',
    );
  }

  bool _isTodaysPendingCollection(DriverOrder o) {
    if (!o.isCashCollectionPending || _promptedPayments.contains(o.id)) {
      return false;
    }
    final d = o.deliveredAt;
    final today = now();
    return d != null &&
        d.year == today.year &&
        d.month == today.month &&
        d.day == today.day;
  }

  @override
  List<ListenableServiceMixin> get listenableServices => [
        _locationService,
        _driverSocketService,
      ];
}

/// Señal interna: se cerró la sesión mientras `connect` estaba en vuelo.
class _LoggedOutDuringConnect implements Exception {
  const _LoggedOutDuringConnect();
}
