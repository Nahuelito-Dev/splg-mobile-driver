import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

DioException offline() =>
    DioException(requestOptions: RequestOptions(path: ''));
DioException rejected(int code) => DioException(
    requestOptions: RequestOptions(path: ''),
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: code,
        data: {'message': 'El pedido ya no está disponible'}));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDialogService dialogs;
  late MockDriverSocketService socket;
  late MockDriverAuthService auth;
  late MockDriverApiService driverApi;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    dialogs = locator<DialogService>() as MockDialogService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    auth = locator<DriverAuthService>() as MockDriverAuthService;
    driverApi = locator<DriverApiService>() as MockDriverApiService;
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
    when(socket.isConnected).thenReturn(true);
    when(socket.hasSocket).thenReturn(true);
    when(trips.activeOrderId).thenReturn(null);
    when(driverApi.profile(refresh: anyNamed('refresh'))).thenAnswer(
        (_) async => const DriverProfile(
            userId: 'u1', fullName: 'Chofer', deliveryId: 'd1'));
  });
  tearDown(() => locator.reset());

  group('H1: la oferta vence con el pop-up de mapas abierto', () {
    testWidgets('se cierran el pop-up y la oferta y se rechaza', (t) async {
      final navKey = GlobalKey<NavigatorState>();
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'pending'));
      when(trips.customerRating(any)).thenAnswer((_) async => null);
      DialogResponse? response;
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => OrderOfferDialog(
                request: DialogRequest(data: {
                  'orderId': 'o1',
                  'expiresAt': DateTime.now()
                      .add(const Duration(seconds: 3))
                      .toIso8601String(),
                }),
                // Igual que el DialogService de stacked: cierra la ruta de
                // ARRIBA, sea cual sea.
                completer: (r) {
                  response = r;
                  navKey.currentState!.pop();
                },
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Aceptar pedido'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Permanecer en SPLG'), findsOneWidget);
      // Vence con el pop-up abierto.
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(response?.confirmed, false);
      expect(find.text('Permanecer en SPLG'), findsNothing);
      expect(find.text('Datos del pedido'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });
  });

  group('H1: el Inicio nunca deja la oferta trabada', () {
    test('si la oferta se rechaza, vuelve a buscar y acepta la siguiente',
        () async {
      final c = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.incomingOrders).thenAnswer((_) => c.stream);
      var n = 0;
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async {
        n++;
        if (n == 1) throw StateError('el diálogo falló');
        return DialogResponse(confirmed: false);
      });
      final api = MockApiClient();
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      when(socket.isConnected).thenReturn(false);
      when(socket.hasSocket).thenReturn(false);
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
      final m = HomeViewModel(trips: trips, apiClient: api);
      await m.connect();
      c.add({'orderId': 'o1'});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(trips.reject('o1')).called(1);
      expect(m.busyWithOrder, false, reason: 'el finally libera _offerOpen');
      c.add({'orderId': 'o2'});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(trips.reject('o2')).called(1);
      await c.close();
    });
  });

  group('H2A: aceptar sin respuesta del back', () {
    HomeViewModel home() => HomeViewModel(trips: trips);

    test('si quedó aceptado por este chofer, sigue sin reintentar', () async {
      when(trips.setStatus('o1', 'accepted')).thenThrow(offline());
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'accepted', deliveryId: 'd1'));
      await home().acceptOrder('o1');
      verify(trips.setStatus('o1', 'accepted')).called(1);
      verify(nav.navigateToDeliveryView(orderId: 'o1')).called(1);
      verifyNever(dialogs.showDialog(
          title: anyNamed('title'), description: anyNamed('description')));
    });

    test('si no quedó aceptado reintenta una vez (misma clave) y sigue',
        () async {
      var calls = 0;
      when(trips.setStatus('o1', 'accepted')).thenAnswer((_) async {
        if (++calls == 1) throw offline();
      });
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'pending'));
      await home().acceptOrder('o1');
      expect(calls, 2);
      verify(nav.navigateToDeliveryView(orderId: 'o1')).called(1);
    });

    test('si de otro chofer o el reintento falla, descarta y lo dice',
        () async {
      when(trips.setStatus('o1', 'accepted')).thenThrow(offline());
      when(trips.order('o1')).thenAnswer(
          (_) async => trip(status: 'accepted', deliveryId: 'otro'));
      await home().acceptOrder('o1');
      verify(trips.setStatus('o1', 'accepted')).called(2);
      verify(dialogs.showDialog(
              title: 'No pudimos aceptar el pedido',
              description: 'Sin conexión. Revisá tu internet.'))
          .called(1);
      verifyNever(nav.navigateToDeliveryView(orderId: 'o1'));
    });

    test('un rechazo del back no se reintenta ni se consulta', () async {
      when(trips.setStatus('o1', 'accepted')).thenThrow(rejected(400));
      await home().acceptOrder('o1');
      verify(trips.setStatus('o1', 'accepted')).called(1);
      verifyNever(trips.order(any));
    });
  });

  group('H2B: retomar el pedido en curso', () {
    void stubOrders(List<DriverOrder> list) => when(driverApi.activeOrder())
        .thenAnswer((_) async => list.isEmpty ? null : list.first);
    DriverOrder o(String id, DriverOrderStatus s) => DriverOrder(
        id: id, status: s, total: 1, createdAt: DateTime(2026, 10, 11));

    test('con un pedido en camino abre su pantalla y retoma el tracking',
        () async {
      stubOrders([o('o9', DriverOrderStatus.onTheWay)]);
      await HomeViewModel(trips: trips).resumeActiveOrder();
      verify(nav.navigateToDeliveryView(orderId: 'o9')).called(1);
      verify(socket.startBroadcasting('o9', 'u1', 'tok')).called(1);
      verify(trips.beginFlow('o9')).called(1);
    });

    test('también con uno aceptado', () async {
      stubOrders([o('o8', DriverOrderStatus.accepted)]);
      await HomeViewModel(trips: trips).resumeActiveOrder();
      verify(nav.navigateToDeliveryView(orderId: 'o8')).called(1);
    });

    test('sin pedidos en curso (204) no hace nada', () async {
      stubOrders([]);
      await HomeViewModel(trips: trips).resumeActiveOrder();
      verifyNever(nav.navigateToDeliveryView(orderId: 'antiguo'));
      verifyNever(nav.navigateToPaymentView(orderId: 'antiguo'));
      verifyNever(trips.beginFlow(any));
    });

    test('un pedido viejo, fuera de los 20 más nuevos, también se retoma',
        () async {
      stubOrders([o('antiguo', DriverOrderStatus.accepted)]);
      await HomeViewModel(trips: trips).resumeActiveOrder();
      verify(nav.navigateToDeliveryView(orderId: 'antiguo')).called(1);
    });

    test('respeta `except`: no reabre el pedido que se acaba de cerrar',
        () async {
      stubOrders([o('o1', DriverOrderStatus.accepted)]);
      await HomeViewModel(trips: trips).resumeActiveOrder(except: 'o1');
      verifyNever(nav.navigateToDeliveryView(orderId: 'o1'));
    });

    test('si la consulta falla no rompe ni abre nada', () async {
      when(driverApi.activeOrder()).thenThrow(Exception('sin red'));
      await HomeViewModel(trips: trips).resumeActiveOrder();
      verifyNever(nav.navigateToDeliveryView(orderId: 'o1'));
    });

    test('si ya hay un flujo activo no abre otra pantalla', () async {
      when(trips.activeOrderId).thenReturn('o1');
      stubOrders([o('o9', DriverOrderStatus.onTheWay)]);
      await HomeViewModel(trips: trips).resumeActiveOrder();
      verifyNever(driverApi.activeOrder());
    });

    test('no se solapan dos búsquedas', () async {
      final gate = Completer<DriverOrder?>();
      when(driverApi.activeOrder()).thenAnswer((_) => gate.future);
      final m = HomeViewModel(trips: trips);
      final a = m.resumeActiveOrder();
      final b = m.resumeActiveOrder();
      gate.complete(null);
      await Future.wait([a, b]);
      verify(driverApi.activeOrder()).called(1);
    });
  });

  group('H3: el Inicio espera el fin REAL del flujo', () {
    test('un pushReplacement no lo retoma; recién Completado sí', () async {
      final api = MockApiClient();
      when(api.patch(any, any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      final real = TripService(api: api, auth: auth);
      final m = HomeViewModel(trips: real);
      var done = false;
      // `navigateToDeliveryView` devuelve apenas la pantalla se reemplaza.
      final f = m.acceptOrder('o1').then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(real.activeOrderId, 'o1');
      expect(done, false,
          reason: 'DeliveryView ya se reemplazó, el flujo no terminó');
      expect(m.search, HomeSearch.idle,
          reason: 'no busca con el chofer en el cobro');
      expect(m.busyWithOrder, true);

      real.endFlow();
      await f;
      expect(done, true);
      expect(real.activeOrderId, isNull);
    });

    test('lo perdido (cancelado) también libera al Inicio', () async {
      final api = MockApiClient();
      when(api.patch(any, any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      final real = TripService(api: api, auth: auth);
      final m = HomeViewModel(trips: real);
      final f = m.acceptOrder('o1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      real.endFlow();
      await f;
      expect(m.busyWithOrder, false);
    });
  });

  group('S4: cierre de sesión', () {
    test('reset descarta las claves de idempotencia y el flujo', () async {
      final api = MockApiClient();
      final keys = <String>[];
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add((i.positionalArguments[3]
            as Map<String, String>)['Idempotency-Key']!);
        if (keys.length == 1) throw offline();
        return Response(requestOptions: RequestOptions(path: ''));
      });
      final svc = TripService(api: api, auth: auth);
      await expectLater(
          svc.setStatus('o1', 'accepted'), throwsA(isA<DioException>()));
      svc.beginFlow('o1');
      svc.reset();
      expect(svc.activeOrderId, isNull);
      await svc.setStatus('o1', 'accepted');
      expect(keys[0], isNot(keys[1]));
    });

    test('logout resetea el servicio', () async {
      final api = MockApiClient();
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      await HomeViewModel(trips: trips, apiClient: api).logout();
      verify(trips.reset()).called(1);
    });
  });

  group('H7: cancelación con el QR abierto', () {
    test('Delivery ignora order:cancelled mientras el QR está arriba',
        () async {
      final c = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.orderCancelled).thenAnswer((_) => c.stream);
      final qr = Completer<void>();
      when(nav.navigateToDeliveryQrView(orderId: 'o1'))
          .thenAnswer((_) => qr.future.then((_) => null));
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      when(trips.customerRating(any)).thenAnswer((_) async => null);
      when(trips.arrived('o1')).thenAnswer((_) async {});
      var homes = 0;
      final m = DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          pollInterval: const Duration(hours: 1),
          iconLoader: () async => null,
          goHome: () => homes++);
      await m.initialize();
      final open = m.arriveAndDeliver();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      clearInteractions(trips);
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'cancelled'));
      c.add({'orderId': 'o1'});
      await Future<void>.delayed(const Duration(milliseconds: 40));
      verifyNever(trips.order(any));
      verifyNever(dialogs.showDialog(
          title: anyNamed('title'), description: anyNamed('description')));
      expect(homes, 0);
      qr.complete();
      await open;
      m.dispose();
      await c.close();
    });
  });

  group('S1: la animación no rearma lo estático', () {
    test('markers y polylines son el mismo objeto mientras nada cambie',
        () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      when(trips.customerRating(any)).thenAnswer((_) async => null);
      final m = DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          pollInterval: const Duration(hours: 1),
          iconLoader: () async => null,
          goHome: () {});
      await m.initialize();
      expect(identical(m.markers, m.markers), true);
      expect(identical(m.polylines, m.polylines), true);
      m.dispose();
    });
  });

  test('TripOrder lee el chofer asignado', () {
    expect(trip(deliveryId: 'd1').deliveryId, 'd1');
    expect(trip().deliveryId, isNull);
    expect(Routes.homeView, isNotEmpty);
  });
}
