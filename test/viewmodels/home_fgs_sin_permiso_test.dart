import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_lib/permissions/app_permission.dart';
import 'package:splg_lib/theme/app_theme.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

/// Una sola regla (`_reconcileOnlineState`) decide en línea + servicio en
/// primer plano + permiso de ubicación:
/// (a) sin permiso y sin entrega → fuera de línea y pantalla de permiso;
/// (b) sin permiso y con entrega → no se corta, franja roja, servicio pendiente;
/// (c) con permiso y en línea → el servicio corre (o se lo baja si no arranca
///     y no hay entrega).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDriverAuthService auth;
  late MockDriverSocketService socket;
  late MockDriverForegroundService foreground;
  late MockDialogService dialogs;
  late MockLocationService location;
  late MockTripService trips;
  late MockDriverApiService driverApi;
  late MockApiClient api;

  const availabilityPath = 'delivery/user/u1/availability';

  /// Estado del plugin y del permiso que ven los mocks.
  late bool permission;
  late bool running;

  void setPermission(bool granted) {
    permission = granted;
    when(location.locationPermission).thenReturn(
        granted ? PermissionOutcome.granted : PermissionOutcome.denied);
    when(location.checkLocationPermission()).thenAnswer((_) async => granted);
    when(location.requestLocationPermission()).thenAnswer((_) async => granted);
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  setUp(() {
    registerServices();
    auth = locator<DriverAuthService>() as MockDriverAuthService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    foreground =
        locator<DriverForegroundService>() as MockDriverForegroundService;
    dialogs = locator<DialogService>() as MockDialogService;
    location = locator<LocationService>() as MockLocationService;
    trips = locator<TripService>() as MockTripService;
    driverApi = locator<DriverApiService>() as MockDriverApiService;
    api = MockApiClient();

    running = false;
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
    when(socket.isConnected).thenReturn(false);
    when(socket.hasSocket).thenReturn(false);
    when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
    when(api.patch(any, any, any)).thenAnswer(
      (_) async => Response(requestOptions: RequestOptions(path: '')),
    );
    when(foreground.canStart()).thenAnswer((_) async => permission);
    when(foreground.start(title: anyNamed('title'), text: anyNamed('text')))
        .thenAnswer((_) async {
      if (permission) running = true;
      return running;
    });
    when(foreground.isRunning).thenAnswer((_) async => running);
    when(foreground.stop()).thenAnswer((_) async => running = false);
    when(driverApi.activeOrder()).thenAnswer((_) async => null);
    setPermission(false);
  });
  tearDown(() {
    HomeView.debugMapBuilder = null;
    HomeView.debugViewModelFactory = null;
    locator.reset();
  });

  HomeViewModel build() => HomeViewModel(apiClient: api);

  /// Conectado con permiso y el servicio corriendo; el socket figura arriba.
  Future<HomeViewModel> online({bool delivery = false}) async {
    setPermission(true);
    final model = build()..hasLocationPermission = true;
    await model.connect(inDelivery: delivery);
    when(socket.isConnected).thenReturn(true);
    expect(model.isOnline, isTrue);
    expect(running, isTrue);
    clearInteractions(api);
    clearInteractions(foreground);
    return model;
  }

  group('(a) sin permiso y sin entrega -', () {
    test(
        'conectarse no lo marca disponible ni abre el socket: queda '
        'desconectado y el Inicio pide el permiso', () async {
      final model = build()..hasLocationPermission = true;

      await model.connect();

      expect(model.isOnline, isFalse);
      verifyNever(api.patch(availabilityPath, {'available': true}, any));
      verifyNever(socket.connect(any, any));
      verifyNever(
          foreground.start(title: anyNamed('title'), text: anyNamed('text')));
      verifyNever(dialogs.showDialog(
          title: anyNamed('title'), description: anyNamed('description')));
      expect(model.hasLocationPermission, isFalse);
      expect(model.permissionMessage, isNotNull);
      expect(model.showsNoLocationBanner, isFalse);
    });

    test(
        'con el servicio figurando corriendo pero sin permiso, tampoco '
        'conecta ni lo marca disponible', () async {
      running = true;
      final model = build()..hasLocationPermission = true;

      await model.connect();

      expect(model.isOnline, isFalse);
      verifyNever(api.patch(availabilityPath, {'available': true}, any));
      verifyNever(socket.connect(any, any));
    });

    test(
        'si el permiso se pierde entre el chequeo y el arranque, se lo baja: '
        'disponible false y sin socket', () async {
      var checks = 0;
      when(foreground.canStart()).thenAnswer((_) async => checks++ == 0);
      final model = build()..hasLocationPermission = true;

      await model.connect();

      verifyInOrder([
        api.patch(availabilityPath, {'available': true}, 'tok'),
        api.patch(availabilityPath, {'available': false}, 'tok'),
      ]);
      verifyNever(socket.connect(any, any));
      verifyNever(dialogs.showDialog(
          title: anyNamed('title'), description: anyNamed('description')));
      expect(model.isOnline, isFalse);
      expect(model.hasLocationPermission, isFalse);
    });

    test(
        'revocado con la app en segundo plano (sin que Android la mate): al '
        'volver se lo baja del todo y se pide el permiso', () async {
      final model = await online();

      setPermission(false);
      when(socket.isConnected).thenReturn(false);
      model.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      verify(api.patch(availabilityPath, {'available': false}, 'tok'))
          .called(greaterThanOrEqualTo(1));
      verify(foreground.stop()).called(greaterThanOrEqualTo(1));
      verify(socket.disconnect()).called(greaterThanOrEqualTo(1));
      expect(running, isFalse);
      expect(model.isOnline, isFalse);
      expect(model.hasLocationPermission, isFalse);
      expect(model.showsNoLocationBanner, isFalse);
    });

    test('al reabrir tras revocar (sin pedido activo) se lo baja del radar',
        () async {
      final model = build();

      model.syncAvailabilityOnOpenForTest();
      await settle();

      verify(api.patch(availabilityPath, {'available': false}, 'tok'))
          .called(1);
      verifyNever(api.patch(availabilityPath, {'available': true}, any));
      expect(model.isOnline, isFalse);
    });

    test('una entrega que termina sin permiso deja al chofer desconectado',
        () async {
      when(trips.activeOrderId).thenReturn('o1');
      final model = build();
      await model.connect(inDelivery: true);
      expect(model.isOnline, isTrue);
      expect(model.showsNoLocationBanner, isTrue);

      when(trips.activeOrderId).thenReturn(null);
      await model.afterFlowForTest('o1');

      // Lo decide el cierre de la entrega, no la búsqueda diferida posterior.
      verify(api.patch(availabilityPath, {'available': false}, 'tok'))
          .called(1);
      expect(model.isOnline, isFalse);
      expect(model.showsNoLocationBanner, isFalse);
      expect(model.hasLocationPermission, isFalse);
      await settle();
    });

    test(
        'la reconexión de entrega se suelta si el back ya no tiene una en '
        'curso: sin permiso, queda desconectado', () async {
      final model = build();
      await model.connect(inDelivery: true);
      expect(model.showsNoLocationBanner, isTrue);

      await model.resumeActiveOrder();
      await settle();

      expect(model.isOnline, isFalse);
      expect(model.showsNoLocationBanner, isFalse);
    });

    test('fuera de línea, un servicio que quedó corriendo se detiene',
        () async {
      running = true;
      final model = build();

      await model.reconcileOnlineStateForTest();

      verify(foreground.stop()).called(1);
      expect(running, isFalse);
    });
  });

  group('(b) sin permiso y con una entrega en curso -', () {
    setUp(() => when(trips.activeOrderId).thenReturn('o1'));

    test('no se corta nada: sigue en línea, sin error, y queda la franja',
        () async {
      final model = build();

      await model.connect(inDelivery: true);

      expect(model.isOnline, isTrue);
      expect(model.foregroundPending, isTrue);
      expect(model.showsNoLocationBanner, isTrue);
      verify(socket.connect('tok', 'u1')).called(1);
      verifyNever(api.patch(any, {'available': false}, any));
      verifyNever(socket.disconnect());
      verifyNever(dialogs.showDialog(
          title: anyNamed('title'), description: anyNamed('description')));
    });

    test(
        'revocado en segundo plano en plena entrega: se para el servicio y '
        'queda la franja, sin bajarlo', () async {
      final model = await online(delivery: true);

      setPermission(false);
      model.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      verify(foreground.stop()).called(greaterThanOrEqualTo(1));
      verifyNever(api.patch(any, {'available': false}, any));
      expect(model.isOnline, isTrue);
      expect(model.showsNoLocationBanner, isTrue);
    });

    test('la franja tapa al aviso amarillo de ubicación', () async {
      when(location.locationUnavailable).thenReturn(true);
      final model = build()..hasLocationPermission = true;

      await model.connect(inDelivery: true);

      expect(model.showsNoLocationBanner, isTrue);
      expect(model.showsLocationAlert, isFalse);
    });

    test('conceder desde la franja arranca el servicio «En reparto»', () async {
      final model = build();
      await model.connect(inDelivery: true);

      setPermission(true);
      await model.requestLocationPermission();

      verify(foreground.start(title: 'En reparto', text: 'Entrega en curso'))
          .called(1);
      expect(model.foregroundPending, isFalse);
      expect(model.showsNoLocationBanner, isFalse);
    });

    test('concedido desde Ajustes: al volver arranca el servicio', () async {
      final model = build();
      await model.connect(inDelivery: true);
      when(socket.isConnected).thenReturn(true);

      setPermission(true);
      model.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(running, isTrue);
      expect(model.foregroundPending, isFalse);
    });

    test('al volver todavía sin permiso no se intenta arrancarlo', () async {
      final model = build();
      await model.connect(inDelivery: true);
      when(socket.isConnected).thenReturn(true);

      model.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      verifyNever(
          foreground.start(title: anyNamed('title'), text: anyNamed('text')));
      expect(model.foregroundPending, isTrue);
    });

    test('desconectarse limpia lo pendiente', () async {
      final model = build();
      await model.connect(inDelivery: true);

      await model.disconnect();

      expect(model.foregroundPending, isFalse);
      expect(model.showsNoLocationBanner, isFalse);
    });
  });

  group('(c) con permiso -', () {
    test('se pone en línea con el servicio «Estás en línea»', () async {
      setPermission(true);
      final model = build()..hasLocationPermission = true;

      await model.connect();

      expect(model.isOnline, isTrue);
      expect(running, isTrue);
      verify(foreground.start(
              title: 'Estás en línea', text: 'Recibiendo pedidos cercanos'))
          .called(1);
    });

    test('en línea con el servicio caído, al volver a la app se arranca',
        () async {
      final model = await online();

      running = false;
      model.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(running, isTrue);
      verify(foreground.start(
              title: 'Estás en línea', text: 'Recibiendo pedidos cercanos'))
          .called(1);
    });

    test(
        'el texto sale de si hay entrega EN ESE MOMENTO: terminada la '
        'entrega, «Estás en línea»', () async {
      when(trips.activeOrderId).thenReturn('o1');
      final model = await online(delivery: true);

      when(trips.activeOrderId).thenReturn(null);
      running = false;
      await model.afterFlowForTest('o1');
      await settle();

      verify(foreground.start(
              title: 'Estás en línea', text: 'Recibiendo pedidos cercanos'))
          .called(1);
      expect(model.isOnline, isTrue);
    });

    test(
        'si el servicio no queda corriendo (estado real) y no hay entrega, '
        'se lo baja', () async {
      setPermission(true);
      when(foreground.start(title: anyNamed('title'), text: anyNamed('text')))
          .thenAnswer((_) async => true);
      when(foreground.isRunning).thenAnswer((_) async => false);
      final model = build()..hasLocationPermission = true;

      await model.connect();

      expect(model.isOnline, isFalse);
      verifyNever(socket.connect(any, any));
    });

    test(
        'con entrega y el servicio que no queda corriendo: franja, sin bajarlo',
        () async {
      setPermission(true);
      when(trips.activeOrderId).thenReturn('o1');
      when(foreground.start(title: anyNamed('title'), text: anyNamed('text')))
          .thenAnswer((_) async => true);
      when(foreground.isRunning).thenAnswer((_) async => false);
      final model = build()..hasLocationPermission = true;

      await model.connect(inDelivery: true);

      expect(model.isOnline, isTrue);
      expect(model.foregroundPending, isTrue);
    });
  });

  group('carreras y reconexión de entrega -', () {
    test(
        'desconectarse con un arranque en vuelo: cuando el arranque termina, '
        'el servicio no queda corriendo', () async {
      setPermission(true);
      final gate = Completer<void>();
      var started = false;
      when(foreground.start(title: anyNamed('title'), text: anyNamed('text')))
          .thenAnswer((_) async {
        started = true;
        await gate.future;
        running = true;
        return true;
      });
      final model = build()..hasLocationPermission = true;

      final connecting = model.connect();
      while (!started) {
        await Future<void>.delayed(Duration.zero);
      }
      await model.disconnect();
      expect(running, isFalse);
      gate.complete();
      await connecting;
      await settle();

      expect(model.isOnline, isFalse);
      expect(running, isFalse);
      verify(foreground.stop()).called(greaterThanOrEqualTo(1));
      verifyNever(socket.connect(any, any));
    });

    DriverOrder enCamino() => DriverOrder(
        id: 'o1',
        status: DriverOrderStatus.onTheWay,
        total: 1,
        createdAt: DateTime(2026, 11, 13),
        customerName: 'Prueba',
        address: 'Calle 1');

    /// Al abrir la app con una entrega en curso en el back: la reconexión
    /// real (`_syncAvailabilityOnOpen` → `connect(inDelivery: true)`). El
    /// flujo de la entrega queda abierto (no termina en el test) y el
    /// TripService simulado no marca `activeOrderId`: sólo queda la marca de
    /// la reconexión.
    Future<HomeViewModel> abrirConEntrega() async {
      when(driverApi.activeOrder()).thenAnswer((_) async => enCamino());
      when(trips.waitFlow()).thenAnswer((_) => Completer<void>().future);
      final model = build();
      model.syncAvailabilityOnOpenForTest();
      await settle();
      return model;
    }

    test(
        'al abrir con una entrega en el back y sin permiso: reconecta, no lo '
        'baja y muestra la franja', () async {
      final model = await abrirConEntrega();

      expect(model.isOnline, isTrue);
      expect(model.showsNoLocationBanner, isTrue);
      verify(socket.connect('tok', 'u1')).called(1);
      verifyNever(api.patch(any, {'available': false}, any));
    });

    test(
        'resumed con sólo la marca de la reconexión: sin permiso no lo baja; '
        'con permiso arranca «En reparto»', () async {
      final model = await abrirConEntrega();
      when(socket.isConnected).thenReturn(true);

      model.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(model.isOnline, isTrue);
      expect(model.showsNoLocationBanner, isTrue);
      verifyNever(api.patch(any, {'available': false}, any));

      setPermission(true);
      model.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      verify(foreground.start(title: 'En reparto', text: 'Entrega en curso'))
          .called(1);
      expect(running, isTrue);
      expect(model.showsNoLocationBanner, isFalse);
    });
  });

  test(
      'dos arranques a la vez: un solo start al plugin y los dos esperan el '
      'mismo resultado', () async {
    final gate = Completer<bool>();
    when(foreground.start(title: anyNamed('title'), text: anyNamed('text')))
        .thenAnswer((_) => gate.future);
    when(foreground.isRunning).thenAnswer((_) async => true);
    final model = build();

    final first = model.startForegroundServiceForTest();
    final second = model.startForegroundServiceForTest();
    gate.complete(true);

    expect(await first, isTrue);
    expect(await second, isTrue);
    verify(foreground.start(title: anyNamed('title'), text: anyNamed('text')))
        .called(1);

    await model.startForegroundServiceForTest();
    verify(foreground.start(title: anyNamed('title'), text: anyNamed('text')))
        .called(1);
  });

  group('franja en el Inicio (vista) -', () {
    late HomeViewModel model;

    Future<void> montar(WidgetTester tester) async {
      HomeView.debugMapBuilder = (_, __) => const SizedBox();
      model = build();
      HomeView.debugViewModelFactory = () => model;
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const HomeView()),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
        'en entrega sin permiso se ve el mapa con la franja roja y el botón '
        'pide el permiso', (tester) async {
      when(trips.activeOrderId).thenReturn('o1');
      await montar(tester);
      await tester.runAsync(() => model.connect(inDelivery: true));
      await tester.pump();

      expect(find.byKey(const Key('home-no-location-banner')), findsOneWidget);
      expect(
          find.text(
              'Sin permiso de ubicación: no se está enviando tu posición'),
          findsOneWidget);
      expect(find.text('Permisos de ubicación requeridos'), findsNothing);

      clearInteractions(location);
      await tester.tap(find.byKey(const Key('home-no-location-banner-action')));
      await tester.pump();
      verify(location.requestLocationPermission()).called(1);
    });

    testWidgets('sin entrega y sin permiso: pantalla de permiso, sin franja',
        (tester) async {
      await montar(tester);
      await tester.runAsync(() => model.connect());
      await tester.pump();

      expect(find.text('Permisos de ubicación requeridos'), findsOneWidget);
      expect(find.byKey(const Key('home-no-location-banner')), findsNothing);
    });
  });
}
