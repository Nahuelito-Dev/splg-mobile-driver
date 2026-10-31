import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.dialogs.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog_model.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

DioException http(int code, [dynamic data]) => DioException(
    requestOptions: RequestOptions(path: ''),
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: code,
        data: data));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDialogService dialogs;
  late MockDriverSocketService socket;
  late MockDriverAuthService auth;
  late MockDriverForegroundService foreground;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    dialogs = locator<DialogService>() as MockDialogService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    auth = locator<DriverAuthService>() as MockDriverAuthService;
    foreground =
        locator<DriverForegroundService>() as MockDriverForegroundService;
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
    when(socket.isConnected).thenReturn(true);
    when(socket.hasSocket).thenReturn(true);
    when(trips.activeOrderId).thenReturn(null);
  });
  tearDown(() {
    NavigationLauncher.launcher = null;
    locator.reset();
  });

  group('modelo de la oferta', () {
    test('carga el pedido y la calificación del cliente', () async {
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'pending'));
      when(trips.customerRating('c1'))
          .thenAnswer((_) async => const RatingSummary(average: 4.5, count: 8));
      final m = OrderOfferDialogModel(trips: trips);
      await m.load('o1');
      expect(m.order!.customerName, 'Cliente Prueba');
      expect(m.customerRating!.count, 8);
      expect(m.loadError, isNull);
      m.dispose();
    });

    test('si falla la lectura queda el error y se puede decidir igual',
        () async {
      when(trips.order('o1')).thenThrow(http(404));
      final m = OrderOfferDialogModel(trips: trips);
      await m.load('o1');
      expect(m.order, isNull);
      expect(m.loadError, 'No encontramos lo que buscabas.');
      m.dispose();
    });

    test('cuenta hasta expiresAt y vence una sola vez', () async {
      final m = OrderOfferDialogModel(trips: trips);
      var expired = 0;
      m.start(DateTime.now().add(const Duration(seconds: 2)).toIso8601String(),
          () => expired++);
      expect(m.totalSeconds, inInclusiveRange(1, 2));
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect(expired, 1);
      expect(m.isFinished, true);
      m.dispose();
    });

    test('decidir a mano frena el vencimiento', () async {
      final m = OrderOfferDialogModel(trips: trips);
      var expired = 0;
      m.start(DateTime.now().add(const Duration(seconds: 1)).toIso8601String(),
          () => expired++);
      m.stop();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(expired, 0);
      m.dispose();
    });

    test('sin expiresAt usa 30 s', () {
      final m = OrderOfferDialogModel(trips: trips);
      m.start(null, () {});
      expect(m.remainingSeconds, 30);
      m.dispose();
    });
  });

  group('Inicio: aceptar y rechazar', () {
    HomeViewModel home() => HomeViewModel(trips: trips);

    test(
        'aceptar: PATCH accepted, tracking, mapa elegido y pantalla del pedido',
        () async {
      final opened = <Uri>[];
      NavigationLauncher.launcher = (u) async {
        opened.add(u);
        return true;
      };
      await home().acceptOrder('o1', map: MapApp.waze, lat: -27.3, lng: -55.9);
      verify(trips.setStatus('o1', 'accepted')).called(1);
      verify(socket.startBroadcasting('o1', 'u1', 'tok')).called(1);
      verify(nav.navigateToDeliveryView(orderId: 'o1')).called(1);
      expect(opened.single.scheme, 'waze');
    });

    test('aceptar eligiendo "Permanecer en SPLG" no abre ningún mapa',
        () async {
      var opened = 0;
      NavigationLauncher.launcher = (u) async {
        opened++;
        return true;
      };
      await home().acceptOrder('o1');
      expect(opened, 0);
      verify(nav.navigateToDeliveryView(orderId: 'o1')).called(1);
    });

    test(
        'si el back rechaza aceptar (la tomó otro) avisa y NO navega ni trackea',
        () async {
      when(trips.setStatus('o1', 'accepted'))
          .thenThrow(http(400, {'message': 'El pedido ya no está disponible'}));
      await home().acceptOrder('o1');
      verify(dialogs.showDialog(
              title: 'No pudimos aceptar el pedido',
              description: 'El pedido ya no está disponible'))
          .called(1);
      verifyNever(socket.startBroadcasting(any, any, any));
      verifyNever(nav.navigateToDeliveryView(orderId: 'o1'));
    });

    test('rechazar llama a reject; un error no rompe', () async {
      await home().rejectOrder('o1');
      verify(trips.reject('o1')).called(1);
      when(trips.reject('o2')).thenThrow(http(500));
      await home().rejectOrder('o2');
    });

    test('al volver del pedido retoma la búsqueda y avisa en línea', () async {
      final m = home();
      await m.acceptOrder('o1');
      verify(foreground.update(title: 'Estás en línea', text: anyNamed('text')))
          .called(1);
    });
  });

  group('Inicio: sincroniza la disponibilidad al abrir', () {
    late MockApiClient api;
    late MockDriverApiService driverApi;
    setUp(() {
      api = MockApiClient();
      driverApi = locator<DriverApiService>() as MockDriverApiService;
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      when(socket.isConnected).thenReturn(false);
      when(socket.hasSocket).thenReturn(false);
    });

    Future<void> abrir() async {
      HomeViewModel(trips: trips, apiClient: api)
          .syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    test('sin pedido en curso, le dice al back que está desconectado',
        () async {
      when(driverApi.activeOrder()).thenAnswer((_) async => null);
      await abrir();
      verify(api.patch(
              'delivery/user/u1/availability', {'available': false}, 'tok'))
          .called(1);
    });

    test('con un pedido en camino no lo baja', () async {
      when(driverApi.activeOrder()).thenAnswer((_) async => DriverOrder(
          id: 'o9',
          status: DriverOrderStatus.onTheWay,
          total: 1,
          createdAt: DateTime(2026)));
      await abrir();
      verifyNever(api.patch(any, any, any));
    });

    test('si no se puede averiguar el pedido en curso, no lo baja', () async {
      when(driverApi.activeOrder()).thenThrow(http(500));
      await abrir();
      verifyNever(api.patch(any, any, any));
    });

    test('con el socket ya conectado no lo baja', () async {
      when(socket.hasSocket).thenReturn(true);
      when(driverApi.activeOrder()).thenAnswer((_) async => null);
      await abrir();
      verifyNever(api.patch(any, any, any));
    });
  });

  group('Inicio: oferta por socket', () {
    HomeViewModel connected() {
      final api = MockApiClient();
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      when(socket.isConnected).thenReturn(false);
      when(socket.hasSocket).thenReturn(false);
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
      return HomeViewModel(trips: trips, apiClient: api);
    }

    test('confirmar la oferta acepta con el mapa y las coordenadas elegidas',
        () async {
      final c = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.incomingOrders).thenAnswer((_) => c.stream);
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async => DialogResponse(
              confirmed: true,
              data: {'map': 'stay', 'lat': -27.3, 'lng': -55.9}));
      final m = connected();
      await m.connect();
      c.add({'orderId': 'o1', 'event': 'NEW_ORDER'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verify(dialogs.showCustomDialog(
              variant: DialogType.orderOffer,
              data: anyNamed('data'),
              barrierDismissible: false))
          .called(1);
      verify(trips.setStatus('o1', 'accepted')).called(1);
      await c.close();
    });

    test('si el diálogo ya aceptó en el back, el Inicio no repite el PATCH',
        () async {
      final c = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.incomingOrders).thenAnswer((_) => c.stream);
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async => DialogResponse(confirmed: true, data: {
                'map': 'stay',
                'lat': -27.3,
                'lng': -55.9,
                'accepted': true
              }));
      final m = connected();
      await m.connect();
      c.add({'orderId': 'o1', 'event': 'NEW_ORDER'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verifyNever(trips.setStatus('o1', 'accepted'));
      await c.close();
    });

    test('si el back ya rechazó desde el diálogo (409), no se repite el PATCH',
        () async {
      final c = StreamController<Map<String, dynamic>>.broadcast();
      when(socket.incomingOrders).thenAnswer((_) => c.stream);
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async => DialogResponse(confirmed: true, data: {
                'map': 'stay',
                'accepted': false,
                'refused': true,
                'error': 'El pedido ya no está disponible'
              }));
      final m = connected();
      await m.connect();
      c.add({'orderId': 'o1', 'event': 'NEW_ORDER'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verifyNever(trips.setStatus('o1', 'accepted'));
      verify(dialogs.showDialog(
              title: 'No pudimos aceptar el pedido',
              description: 'El pedido ya no está disponible'))
          .called(1);
      await c.close();
    });

    test('una segunda oferta mientras hay una abierta se rechaza explícito',
        () async {
      final c = StreamController<Map<String, dynamic>>.broadcast();
      final gate = Completer<DialogResponse?>();
      when(socket.incomingOrders).thenAnswer((_) => c.stream);
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) => gate.future);
      final m = connected();
      await m.connect();
      c.add({'orderId': 'o1'});
      c.add({'orderId': 'o2'});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      verify(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .called(1);
      gate.complete(DialogResponse(confirmed: false));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      verify(trips.reject('o1')).called(1);
      verify(trips.reject('o2')).called(1);
      await c.close();
    });
  });
}
