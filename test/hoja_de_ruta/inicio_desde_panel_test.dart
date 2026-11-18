import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

/// El administrador inicia la hoja de ruta desde el panel: el back avisa
/// `route-sheet:started` y la app abre sola la primera parada, sin que el chofer
/// tenga que reabrirla.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDriverSocketService socket;
  late MockDriverAuthService auth;
  late MockDriverApiService driverApi;
  late StreamController<void> started;
  late StreamController<Map<String, dynamic>> offers;
  late StreamController<Map<String, dynamic>> cancelled;
  late Completer<void> flow;
  String? active;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    auth = locator<DriverAuthService>() as MockDriverAuthService;
    driverApi = locator<DriverApiService>() as MockDriverApiService;
    started = StreamController<void>.broadcast();
    offers = StreamController<Map<String, dynamic>>.broadcast();
    cancelled = StreamController<Map<String, dynamic>>.broadcast();
    flow = Completer<void>();
    active = null;
    when(trips.activeOrderId).thenAnswer((_) => active);
    when(trips.beginFlow(any)).thenAnswer((i) {
      active = i.positionalArguments.first as String;
    });
    when(trips.endFlow()).thenAnswer((_) => active = null);
    when(trips.waitFlow()).thenAnswer((_) => flow.future);
    when(socket.routeSheetStarted).thenAnswer((_) => started.stream);
    when(socket.incomingOrders).thenAnswer((_) => offers.stream);
    when(socket.orderCancelled).thenAnswer((_) => cancelled.stream);
    when(socket.isConnected).thenReturn(false);
    when(socket.hasSocket).thenReturn(false);
    when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
    when(driverApi.profile(refresh: anyNamed('refresh'))).thenAnswer(
        (_) async => const DriverProfile(
            userId: 'u1', fullName: 'Chofer', deliveryId: 'd1'));
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
  });

  final vms = <HomeViewModel>[];

  tearDown(() async {
    if (!flow.isCompleted) flow.complete();
    for (final m in vms) {
      try {
        m.dispose();
      } catch (_) {}
    }
    vms.clear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await started.close();
    await offers.close();
    await cancelled.close();
    NavigationLauncher.launcher = null;
    locator.reset();
  });

  Future<HomeViewModel> conectado() async {
    final api = MockApiClient();
    when(api.patch(any, any, any)).thenAnswer(
        (_) async => Response(requestOptions: RequestOptions(path: '')));
    final m = HomeViewModel(trips: trips, apiClient: api);
    vms.add(m);
    await m.connect();
    return m;
  }

  Future<void> pausa() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  test('el panel inicia la hoja: la app abre la primera parada sola', () async {
    when(driverApi.activeOrder()).thenAnswer((_) async => null);
    await conectado();
    await pausa();
    verifyNever(nav.navigateToDeliveryView(orderId: 'p1'));

    // Al iniciar el viaje, el back ya tiene la primera parada en camino.
    when(driverApi.activeOrder()).thenAnswer((_) async => DriverOrder(
        id: 'p1',
        status: DriverOrderStatus.accepted,
        total: 1,
        createdAt: DateTime(2026, 11, 18),
        customerName: 'Gonzalo Aguirre',
        address: 'Santiago del Estero 545'));
    started.add(null);
    await pausa();

    verify(nav.navigateToDeliveryView(orderId: 'p1')).called(1);
  });

  test('el aviso llega mientras otra retoma consulta: no se pierde', () async {
    // La primera consulta (la de conectarse) tarda y vuelve vacía: el back
    // todavía no había guardado el inicio de la hoja.
    final lenta = Completer<DriverOrder?>();
    when(driverApi.activeOrder()).thenAnswer((_) => lenta.future);
    await conectado();
    await pausa();

    started.add(null); // llega con la retoma en curso
    await pausa();
    when(driverApi.activeOrder()).thenAnswer((_) async => DriverOrder(
        id: 'p2',
        status: DriverOrderStatus.accepted,
        total: 1,
        createdAt: DateTime(2026, 11, 18),
        customerName: 'Martina Acosta',
        address: 'Jujuy 571'));
    lenta.complete(null);
    await pausa();

    verify(nav.navigateToDeliveryView(orderId: 'p2')).called(1);
  });

  test('con una entrega en curso, el aviso no abre otra', () async {
    when(driverApi.activeOrder()).thenAnswer((_) async => null);
    await conectado();
    await pausa();
    active = 'p0'; // ya está entregando
    clearInteractions(driverApi);

    started.add(null);
    await pausa();

    verifyNever(driverApi.activeOrder());
    verifyNever(nav.navigateToDeliveryView(orderId: 'p0'));
  });
}
