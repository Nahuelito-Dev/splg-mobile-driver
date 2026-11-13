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

/// La asignación manual del admin (`PATCH /orders/:id/assign/:deliveryId`)
/// llega por `server:new-order-request` con `assigned: true`. No es una oferta:
/// nunca se muestra con cuenta regresiva ni se rechaza; abre la entrega (o queda
/// como «Tu próximo pedido»), una sola vez, y no se pierde si el chofer está
/// ocupado. Sin el campo es una oferta como siempre.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDialogService dialogs;
  late MockDriverSocketService socket;
  late MockDriverAuthService auth;
  late MockDriverApiService driverApi;
  late StreamController<Map<String, dynamic>> offers;
  late StreamController<Map<String, dynamic>> cancelled;

  /// Pedido activo del TripService simulado (como el real: lo marca
  /// `beginFlow` y lo suelta `endFlow`); la entrega no termina sola.
  String? active;
  late Completer<void> flow;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    dialogs = locator<DialogService>() as MockDialogService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    auth = locator<DriverAuthService>() as MockDriverAuthService;
    driverApi = locator<DriverApiService>() as MockDriverApiService;
    offers = StreamController<Map<String, dynamic>>.broadcast();
    cancelled = StreamController<Map<String, dynamic>>.broadcast();
    active = null;
    flow = Completer<void>();
    when(trips.activeOrderId).thenAnswer((_) => active);
    when(trips.beginFlow(any)).thenAnswer((i) {
      active = i.positionalArguments.first as String;
    });
    when(trips.endFlow()).thenAnswer((_) => active = null);
    when(trips.waitFlow()).thenAnswer((_) => flow.future);
    when(socket.orderCancelled).thenAnswer((_) => cancelled.stream);
    when(driverApi.profile(refresh: anyNamed('refresh'))).thenAnswer(
        (_) async => const DriverProfile(
            userId: 'u1', fullName: 'Chofer', deliveryId: 'd1'));
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
    when(socket.isConnected).thenReturn(false);
    when(socket.hasSocket).thenReturn(false);
    when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
    when(socket.incomingOrders).thenAnswer((_) => offers.stream);
    when(dialogs.showCustomDialog(
            variant: anyNamed('variant'),
            data: anyNamed('data'),
            barrierDismissible: anyNamed('barrierDismissible')))
        .thenAnswer((_) async => DialogResponse(confirmed: false));
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

  Map<String, dynamic> aviso(String id, {bool assigned = true}) => {
        'event': 'NEW_ORDER',
        'orderId': id,
        'totalAmount': 16000,
        'paymentMethod': 'cash',
        'expiresAt':
            DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
        'items': [],
        if (assigned) 'assigned': true,
      };

  Future<void> pausa() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  DriverOrder pedido(String id, DriverOrderStatus s) => DriverOrder(
      id: id,
      status: s,
      total: 1,
      createdAt: DateTime(2026, 11, 12),
      customerName: 'Prueba Tres',
      address: 'Colón 1520');

  void sinOferta() => verifyNever(dialogs.showCustomDialog(
      variant: anyNamed('variant'),
      data: anyNamed('data'),
      barrierDismissible: anyNamed('barrierDismissible')));

  test('libre: va directo a la entrega, sin oferta ni rechazo', () async {
    await conectado();
    offers.add(aviso('oM'));
    await pausa();

    sinOferta();
    verifyNever(trips.reject(any));
    verifyNever(trips.setStatus('oM', 'accepted'));
    verify(nav.navigateToDeliveryView(orderId: 'oM')).called(1);
  });

  test('el aviso duplicado no abre dos entregas ni dos transmisiones',
      () async {
    final m = await conectado();
    offers
      ..add(aviso('oM'))
      ..add(aviso('oM'));
    await pausa();

    verify(nav.navigateToDeliveryView(orderId: 'oM')).called(1);
    verify(socket.startBroadcasting('oM', any, any)).called(1);
    expect(m.assignedWaiting, isEmpty);
    verifyNever(trips.reject(any));
  });

  test('el aviso y la retoma al reconectar no abren dos entregas', () async {
    final m = await conectado();
    when(driverApi.activeOrder())
        .thenAnswer((_) async => pedido('oM', DriverOrderStatus.accepted));
    // La sesión tarda: la entrega asignada queda abriéndose y en ese momento
    // la reconexión pide retomar.
    final sesion = Completer<String>();
    when(auth.token).thenAnswer((_) => sesion.future);
    offers.add(aviso('oM'));
    await pausa();
    final retoma = m.resumeActiveOrder();
    sesion.complete('tok');
    await pausa();

    verify(nav.navigateToDeliveryView(orderId: 'oM')).called(1);
    verify(socket.startBroadcasting('oM', any, any)).called(1);
    unawaited(retoma);
  });

  test('con una entrega en curso queda como «Tu próximo pedido»', () async {
    active = 'oA';
    final m = await conectado();
    offers.add(aviso('oB'));
    await pausa();

    expect(m.queuedOrderId, 'oB');
    verifyNever(trips.reject(any));
    verifyNever(nav.navigateToDeliveryView(orderId: 'oB'));
    verify(dialogs.showDialog(
            title: 'Tu próximo pedido', description: anyNamed('description')))
        .called(1);
  });

  test(
      'con la entrega retomada al abrir la app, la asignación queda como '
      '«Tu próximo pedido» (sin colgarse)', () async {
    final m = await conectado();
    when(driverApi.activeOrder())
        .thenAnswer((_) async => pedido('oA', DriverOrderStatus.onTheWay));
    // La retoma abre la entrega y queda esperándola (no termina).
    unawaited(m.resumeActiveOrder(collect: false));
    await pausa();
    expect(active, 'oA');

    offers.add(aviso('oB'));
    await pausa().timeout(const Duration(seconds: 2));

    expect(m.queuedOrderId, 'oB');
    verifyNever(trips.reject(any));
    verify(dialogs.showDialog(
            title: 'Tu próximo pedido', description: anyNamed('description')))
        .called(1);
  });

  test(
      'ocupado y con la cola llena: la asignación no se pierde y se abre al '
      'terminar', () async {
    active = 'oA';
    final m = await conectado();
    offers.add(aviso('oB'));
    await pausa();
    offers.add(aviso('oC'));
    await pausa();

    expect(m.queuedOrderId, 'oB');
    expect(m.assignedWaiting, ['oC']);
    verifyNever(trips.reject(any));

    // Terminó A y B: el back da C como el pedido en curso.
    active = null;
    when(driverApi.activeOrder())
        .thenAnswer((_) async => pedido('oC', DriverOrderStatus.accepted));
    unawaited(m.resumeActiveOrder(collect: false));
    await pausa();

    verify(nav.navigateToDeliveryView(orderId: 'oC')).called(1);
    expect(m.assignedWaiting, isEmpty);
    verify(dialogs.showDialog(
            title: 'Tu próximo pedido',
            description: argThat(contains('te asignó la distribuidora'),
                named: 'description')))
        .called(1);
  });

  test(
      'con una oferta en pantalla la asignación espera y se abre cuando la '
      'oferta se cierra', () async {
    final decision = Completer<DialogResponse?>();
    when(dialogs.showCustomDialog(
            variant: anyNamed('variant'),
            data: anyNamed('data'),
            barrierDismissible: anyNamed('barrierDismissible')))
        .thenAnswer((_) => decision.future);
    final m = await conectado();
    offers.add(aviso('oP', assigned: false));
    await pausa();
    offers.add(aviso('oM'));
    await pausa();

    expect(m.assignedWaiting, ['oM']);
    verifyNever(nav.navigateToDeliveryView(orderId: 'oM'));

    when(driverApi.activeOrder())
        .thenAnswer((_) async => pedido('oM', DriverOrderStatus.accepted));
    decision.complete(DialogResponse(confirmed: false));
    await pausa();

    verify(trips.reject('oP')).called(1);
    verifyNever(trips.reject('oM'));
    verify(nav.navigateToDeliveryView(orderId: 'oM')).called(1);
    expect(m.assignedWaiting, isEmpty);
  });

  test(
      'la oferta del mismo pedido abierta cuando llega la asignación: al '
      'cerrarse no se rechaza y se abre la entrega', () async {
    final decision = Completer<DialogResponse?>();
    when(dialogs.showCustomDialog(
            variant: anyNamed('variant'),
            data: anyNamed('data'),
            barrierDismissible: anyNamed('barrierDismissible')))
        .thenAnswer((_) => decision.future);
    final m = await conectado();
    offers.add(aviso('oM', assigned: false));
    await pausa();
    offers.add(aviso('oM'));
    await pausa();

    when(driverApi.activeOrder())
        .thenAnswer((_) async => pedido('oM', DriverOrderStatus.accepted));
    // La oferta vence (o el chofer toca «Volver»).
    decision.complete(DialogResponse(confirmed: false));
    await pausa();

    verifyNever(trips.reject('oM'));
    verify(nav.navigateToDeliveryView(orderId: 'oM')).called(1);
    expect(m.assignedWaiting, isEmpty);
  });

  test('si el pedido en espera se cancela, deja de esperar', () async {
    active = 'oA';
    final m = await conectado();
    offers.add(aviso('oB'));
    await pausa();
    offers.add(aviso('oC'));
    await pausa();

    cancelled.add({'orderId': 'oC'});
    await pausa();
    expect(m.assignedWaiting, isEmpty);
  });

  test(
      'sin `assigned` es una oferta como siempre: se muestra y, si la deja '
      'pasar, se rechaza', () async {
    await conectado();
    offers.add(aviso('oP', assigned: false));
    await pausa();

    verify(dialogs.showCustomDialog(
            variant: anyNamed('variant'),
            data: anyNamed('data'),
            barrierDismissible: anyNamed('barrierDismissible')))
        .called(1);
    verify(trips.reject('oP')).called(1);
    verifyNever(nav.navigateToDeliveryView(orderId: 'oP'));
  });
}
