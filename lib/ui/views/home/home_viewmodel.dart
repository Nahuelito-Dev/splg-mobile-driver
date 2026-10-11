import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:uuid/uuid.dart';

import 'package:splg_driver/app/app.dialogs.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/app_permissions.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/location_service.dart';
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
  }) : _apiClient = apiClient ?? ApiClient();

  /// Cuánto se muestra "Buscando pedidos…" antes de pasar a "Sin pedidos
  /// disponibles" si no llegó ninguna oferta.
  final Duration searchTimeout;

  final _locationService = locator<LocationService>();
  final _navigationService = locator<NavigationService>();
  final _driverSocketService = locator<DriverSocketService>();
  final _dialogService = locator<DialogService>();
  final _foregroundService = locator<DriverForegroundService>();
  final ApiClient _apiClient;
  final _permissions = locator<AppPermissions>();
  final _uuid = const Uuid();

  // Lazy a propósito (no como los demás `locator<T>()` de arriba): resolver
  // DriverAuthService dispara `FirebaseAuth.instance` en su constructor, y
  // este ViewModel se instancia cada vez que se construye HomeView (incluso
  // en tests/goldens que no inicializan Firebase). Como getter, solo se
  // resuelve cuando efectivamente se usa (connect/acceptOrder/onData).
  DriverAuthService get _driverAuthService => locator<DriverAuthService>();

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
    await _resolveLocation(interactive: true);
    await loadToday();
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
    if (state == AppLifecycleState.resumed && !hasLocationPermission) {
      _resolveLocation(interactive: false);
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _incomingOrdersSubscription?.cancel();
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

    // Animar la cámara hacia la nueva ubicación (solo la primera vez)
    if (markers.length == 1) {
      _animateCameraToPosition(currentLocation!);
    }

    notifyListeners();
  }

  /// Anima la cámara hacia una posición específica
  Future<void> _animateCameraToPosition(LatLng position) async {
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

  /// Centra el mapa en la ubicación actual del usuario
  Future<void> centerOnUserLocation() async {
    if (currentLocation != null) {
      await _animateCameraToPosition(currentLocation!);
    }
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

  void _subscribeToIncomingOrders() {
    _incomingOrdersSubscription?.cancel();
    _incomingOrdersSubscription =
        _driverSocketService.incomingOrders.listen(_showOrderOfferDialog);
  }

  /// Muestra el dialog de "Nuevo pedido" por cada oferta que llega
  /// (`server:new-order-request` / `NEW_ORDER` | `NEW_ORDER_RETRY`).
  Future<void> _showOrderOfferDialog(Map<String, dynamic> offer) async {
    final orderId = offer['orderId']?.toString();
    if (orderId == null) {
      debugPrint('Oferta de pedido sin orderId, se ignora: $offer');
      return;
    }

    final response = await _dialogService.showCustomDialog(
      variant: DialogType.orderOffer,
      data: offer,
    );

    if (response?.confirmed == true) {
      await acceptOrder(orderId);
    } else {
      await rejectOrder(orderId);
      if (isOnline) {
        _startSearching();
        notifyListeners();
      }
    }
  }

  /// Rechaza una oferta (CU-016): `POST /orders/:orderId/reject`. El backend
  /// cierra la oferta y re-ofrece al siguiente chofer de inmediato. Best-effort.
  Future<void> rejectOrder(String orderId) async {
    final token = await _driverAuthService.token;
    if (token == null) return;
    try {
      await _apiClient.post(
        'orders/$orderId/reject',
        const {},
        token,
        {'Idempotency-Key': _uuid.v4()},
      );
      debugPrint('Oferta $orderId rechazada por el chofer');
    } catch (e) {
      debugPrint('Error rechazando la oferta $orderId: $e');
    }
  }

  /// Acepta un pedido ofertado: PATCH idempotente a `/orders/:orderId/status`
  /// con `status: accepted`. Si el backend confirma, arranca el broadcasting
  /// de posición GPS de la entrega.
  Future<void> acceptOrder(String orderId) async {
    final token = await _driverAuthService.token;
    final userId = _driverAuthService.userId;
    if (token == null || userId == null) {
      debugPrint('No se puede aceptar el pedido $orderId: falta la sesión');
      return;
    }

    try {
      final response = await _apiClient.patch(
        'orders/$orderId/status',
        {'status': 'accepted'},
        token,
        {'Idempotency-Key': _uuid.v4()},
      );

      if (response.statusCode == 200) {
        debugPrint('Pedido $orderId aceptado');
        _driverSocketService.startBroadcasting(orderId, userId, token);
        await _foregroundService.update(
          title: 'En reparto',
          text: 'Entrega en curso',
        );
        await _navigationService.navigateToDeliveryView(orderId: orderId);
      } else {
        debugPrint(
            'No se pudo aceptar el pedido $orderId: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error aceptando el pedido $orderId: $e');
    }
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
