import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.dialogs.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/fcm_service.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'package:splg_driver/services/maintenance_repository.dart';
import 'package:splg_driver/services/app_permissions.dart';
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

  // Lazy, por lo mismo que `_driverAuthService`.
  DriverApiService get _driverApi => locator<DriverApiService>();

  Completer<GoogleMapController> mapController = Completer();

  HomeSearch search = HomeSearch.idle;
  Timer? _searchTimer;

  /// Reloj inyectable para los tests.
  DateTime Function() now = DateTime.now;

  /// Total entregado hoy y cantidad de entregas; el chip del Inicio sólo se
  /// muestra si hay alguna.
  num todayTotal = 0;
  int todayCount = 0;

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

  // Posición inicial del mapa (Buenos Aires, Argentina como ejemplo)
  static const CameraPosition initialPosition = CameraPosition(
    target: LatLng(-34.6037, -58.3816),
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

  // @override
  // void onError(error) {
  //   debugPrint('Error en el stream de ubicación: $error');
  //   permissionMessage = 'Error al obtener la ubicación';
  //   notifyListeners();
  // }

  /// Inicializa el ViewModel: pide el permiso de ubicación (con explicación) y
  /// empieza el tracking si se concede.
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _startLoadPolling();
    await _resolveLocation(interactive: true);
    await loadToday();
    await refreshNoOrdersReason();
    unawaited(resumeActiveOrder());
    _listenMaintenanceTaps();
    _maintenanceChanges?.cancel();
    _maintenanceChanges = _notifier.changes.listen((_) => notifyListeners());
    unawaited(_notifier.sync());
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

  /// Total de hoy para el chip del Inicio, con las entregas más recientes del
  /// chofer (`GET /orders/delivery/:id`, de la más nueva a la más vieja). Si
  /// falla no se muestra nada.
  Future<void> loadToday() async {
    try {
      final page =
          await _driverApi.ordersPage(limit: DriverApiService.maxPageSize);
      final summary = EarningsSummary.from(page.orders, now());
      todayTotal = summary.today;
      todayCount = summary.todayCount;
    } catch (e) {
      debugPrint('No se pudo leer el total de hoy: $e');
      todayTotal = 0;
      todayCount = 0;
    }
    notifyListeners();
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
      if (!hasLocationPermission) _resolveLocation(interactive: false);
      if (_isHomeVisible()) unawaited(refreshNoOrdersReason());
      unawaited(resumeActiveOrder());
      unawaited(_notifier.sync());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopLoadPolling();
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _loadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _incomingOrdersSubscription?.cancel();
    _rejectedSubscription?.cancel();
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
      hasLocationPermission = interactive
          ? await _locationService.requestLocationPermission()
          : await _locationService.checkLocationPermission();

      if (hasLocationPermission) {
        permissionMessage = null;
        await _locationService.startTracking();
      } else if (_locationService.serviceDisabled) {
        permissionMessage =
            'El GPS del teléfono está apagado. Encendelo para ponerte en línea.';
      } else if (_locationService.locationPermission ==
          PermissionOutcome.permanentlyDenied) {
        permissionMessage = 'La ubicación está desactivada para SPLG.\n'
            'Activala desde Ajustes para ponerte en línea y recibir pedidos.';
      } else {
        permissionMessage =
            'Necesitamos tu ubicación para asignarte pedidos cercanos.';
      }
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
    _sessionEpoch++;
    try {
      final inFlight = _connectInFlight;
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {}
      }
      await _rollbackOnline();

      // Detener el seguimiento de ubicación
      await _locationService.stopTracking();

      // Cerrar la sesión de verdad: sin esto la app la restaura al reabrir.
      await _driverAuthService.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión: $e');
    } finally {
      // Las claves de idempotencia y el flujo en curso son de la sesión.
      _trips.reset();
      _notifier.reset();
      _fcm.clearPendingMaintenance();
      _board.reset();
      _maintenanceRepo.reset();
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
  Future<void> connect() {
    if (isConnected || _connecting || _connectInFlight != null) {
      debugPrint('connect() ignorado: el chofer ya está conectado');
      return Future.value();
    }
    final run = _connect();
    _connectInFlight = run;
    notifyListeners();
    return run.whenComplete(() {
      if (identical(_connectInFlight, run)) _connectInFlight = null;
    });
  }

  Future<void> _connect() async {
    final epoch = _sessionEpoch;
    if (isConnected || _connecting) {
      debugPrint('connect() ignorado: el chofer ya está conectado');
      return;
    }

    final userId = _driverAuthService.userId;
    final token = await _driverAuthService.token;
    if (userId == null || token == null) {
      debugPrint('No se puede conectar: falta la sesión del chofer');
      return;
    }

    _connecting = true;
    try {
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
      await _foregroundService.start(
        title: 'Estás en línea',
        text: 'Recibiendo pedidos cercanos',
      );
      _abortIfLoggedOut(epoch);

      _driverSocketService.connect(token, userId);
      if (!await _driverSocketService.waitUntilConnected(_socketTimeout)) {
        throw StateError('el socket no conectó');
      }
      _abortIfLoggedOut(epoch);

      // Registra la posición actual en el GEO apenas se conecta, sin esperar
      // al próximo tick del tracking de ubicación.
      final position = _locationService.currentPosition ??
          await _locationService.getCurrentLocation();
      if (position != null) {
        _driverSocketService.sendLocation(
          userId,
          position.latitude,
          position.longitude,
        );
      }

      _subscribeToIncomingOrders();
      _startSearching();
      unawaited(resumeActiveOrder());
    } on _LoggedOutDuringConnect {
      debugPrint('connect() abortado: se cerró la sesión mientras conectaba');
      await _rollbackOnline();
    } catch (e) {
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

  void _abortIfLoggedOut(int epoch) {
    if (epoch != _sessionEpoch) throw const _LoggedOutDuringConnect();
  }

  /// Deja al chofer fuera de línea sin depender del estado del socket.
  Future<void> _rollbackOnline() async {
    _markedOnline = false;
    _stopSearching();
    await _setAvailability(false);
    await _foregroundService.stop();
    _incomingOrdersSubscription?.cancel();
    _incomingOrdersSubscription = null;
    _rejectedSubscription?.cancel();
    _rejectedSubscription = null;
    _notifier.stop();
    _board.detach();
    _driverSocketService.disconnect();
  }

  /// Desconecta al chofer: se marca NO DISPONIBLE (el backend lo saca del radar),
  /// deja de recibir ofertas y cierra el socket.
  Future<void> disconnect() async {
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

  /// El servidor cortó el socket varias veces seguidas apenas conectar: la
  /// sesión no es válida. Se baja al chofer de línea y se le avisa.
  Future<void> _onSocketRejected() async {
    // Se lee antes de volver a fuera de línea: cerrar el socket lo limpia.
    final revoked = _driverSocketService.accessRevoked;
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

  void _subscribeToIncomingOrders() {
    _rejectedSubscription?.cancel();
    _rejectedSubscription =
        _driverSocketService.rejected.listen((_) => _onSocketRejected());
    _incomingOrdersSubscription?.cancel();
    _incomingOrdersSubscription =
        _driverSocketService.incomingOrders.listen(_showOrderOfferDialog);
    _board.bind(_driverAuthService.userId);
    _board.attach(_driverSocketService.maintenanceEvents);
    _notifier.isBusyWithOrder = () => _trips.activeOrderId != null;
    _notifier.start();
    unawaited(_notifier.sync());
  }

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

  /// Hay una oferta abierta o un pedido en curso.
  @visibleForTesting
  bool get busyWithOrder => _offerOpen || _trips.activeOrderId != null;

  Future<void> _showOrderOfferDialog(Map<String, dynamic> offer) async {
    final orderId = offer['orderId']?.toString();
    if (orderId == null) {
      debugPrint('Oferta de pedido sin orderId, se ignora: $offer');
      return;
    }
    // Mientras se busca un pedido para retomar, la oferta espera la decisión:
    // si no, el diálogo y la pantalla del pedido retomado se pisarían.
    final deciding = _resumeDecision;
    if (_resuming && deciding != null) await deciding.future;
    if (_offerOpen || _trips.activeOrderId != null) {
      // Ocupado: se rechaza explícitamente para que el back la pase a otro
      // chofer enseguida, en vez de esperar a que venza.
      debugPrint('Oferta $orderId rechazada: ya hay un pedido en pantalla');
      await rejectOrder(orderId);
      return;
    }
    _offerOpen = true;
    // La oferta tiene prioridad: un aviso de taller abierto se cierra y vuelve después.
    _notifier.offerStarted();
    try {
      final response = await _dialogService.showCustomDialog(
        variant: DialogType.orderOffer,
        data: offer,
        barrierDismissible: false,
      );

      if (response?.confirmed == true) {
        final data = response?.data;
        final map = data is Map
            ? MapApp.values.firstWhere((m) => m.name == data['map'],
                orElse: () => MapApp.stay)
            : MapApp.stay;
        final lat = data is Map ? (data['lat'] as num?)?.toDouble() : null;
        final lng = data is Map ? (data['lng'] as num?)?.toDouble() : null;
        await acceptOrder(orderId, map: map, lat: lat, lng: lng);
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
      _notifier.offerEnded(pump: done == null);
      if (done != null) _resumeSoon(done);
    }
  }

  /// Rechaza una oferta (CU-016): `POST /orders/:orderId/reject`. El backend
  /// cierra la oferta y re-ofrece al siguiente chofer de inmediato. Best-effort.
  Future<void> rejectOrder(String orderId) async {
    try {
      await _trips.reject(orderId);
      debugPrint('Oferta $orderId rechazada por el chofer');
    } catch (e) {
      debugPrint('Error rechazando la oferta $orderId: $e');
    }
  }

  /// Acepta un pedido ofertado: `PATCH /orders/:orderId/status {accepted}`
  /// (idempotente). Si el back lo confirma, arranca el tracking de la entrega,
  /// abre el mapa elegido y va a la pantalla del pedido; si lo rechaza (la oferta
  /// venció o la tomó otro chofer) lo dice y vuelve a buscar.
  Future<void> acceptOrder(
    String orderId, {
    MapApp map = MapApp.stay,
    double? lat,
    double? lng,
  }) async {
    final token = await _driverAuthService.token;
    final userId = _driverAuthService.userId;
    if (token == null || userId == null) {
      debugPrint('No se puede aceptar el pedido $orderId: falta la sesión');
      return;
    }

    if (!await _acceptWithConfirmation(orderId)) {
      if (isOnline) {
        _startSearching();
        notifyListeners();
      }
      return;
    }
    debugPrint('Pedido $orderId aceptado');
    await _runOrderFlow(orderId,
        token: token, userId: userId, map: map, lat: lat, lng: lng);
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
    _driverSocketService.startBroadcasting(orderId, userId, token);
    await _foregroundService.update(
      title: 'En reparto',
      text: 'Entrega en curso',
    );
    if (map != MapApp.stay && lat != null && lng != null) {
      unawaited(NavigationLauncher.open(map, lat, lng));
    }
    await _navigationService.navigateToDeliveryView(orderId: orderId);
    await _trips.waitFlow();
    await _afterFlow(orderId);
  }

  /// Pedido entregado en efectivo y sin cobrar (la app se cerró en medio del
  /// cobro): se retoma directo en la pantalla de cobro.
  Future<void> _runPaymentFlow(String orderId) async {
    // Una sola vez por sesión: si lo deja para después ("Más tarde"), no se
    // le vuelve a abrir solo.
    _promptedPayments.add(orderId);
    _trips.beginFlow(orderId);
    _stopSearching();
    await _navigationService.navigateToPaymentView(orderId: orderId);
    await _trips.waitFlow();
    await _afterFlow(orderId);
  }

  /// Pedido que terminó su flujo hace un instante: el reintento de retomar
  /// lo saltea para no volver a abrir el mismo si quedó sin terminar.
  String? _justFinished;

  /// Cobros que ya se le abrieron al chofer en esta sesión.
  final Set<String> _promptedPayments = {};

  Future<void> _afterFlow(String orderId) async {
    await _foregroundService.update(
      title: 'Estás en línea',
      text: 'Recibiendo pedidos cercanos',
    );
    earned = _trips.takeEarned();
    if (isOnline) _startSearching();
    notifyListeners();
    await loadToday();
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
    unawaited(Future<void>.delayed(
        Duration.zero,
        () => resumeActiveOrder(except: except, collect: false)
            // Terminado el pedido (y el que se haya retomado): los avisos de
            // taller que esperaban pueden salir.
            .whenComplete(notifier.recheck)));
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
  Future<void> resumeActiveOrder({String? except, bool collect = true}) async {
    if (_resuming || _offerOpen || _trips.activeOrderId != null) return;
    _resuming = true;
    final decision = _resumeDecision = Completer<void>();
    try {
      final token = await _driverAuthService.token;
      final userId = _driverAuthService.userId;
      if (token == null || userId == null) return;
      final order = await _driverApi.activeOrder();
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
      if (_offerOpen || _trips.activeOrderId != null) return;
      if (current != null) {
        debugPrint('Retomando el pedido en curso ${current.id}');
        // La oferta que espera se reanuda en un microtask, cuando el flujo ya
        // marcó el pedido como activo (primera línea de `_runOrderFlow`).
        decision.complete();
        await _runOrderFlow(current.id, token: token, userId: userId);
      } else if (toCollect != null) {
        debugPrint('Retomando el cobro del pedido ${toCollect.id}');
        decision.complete();
        await _runPaymentFlow(toCollect.id);
      }
    } catch (e) {
      debugPrint('No se pudo buscar un pedido en curso: $e');
    } finally {
      _resuming = false;
      if (!decision.isCompleted) decision.complete();
    }
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

  /// Monto del último pedido terminado, para el cartel "¡Ganaste!" del mapa.
  num? earned;

  /// Cierra el cartel "¡Ganaste!".
  void dismissEarned() {
    earned = null;
    notifyListeners();
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
