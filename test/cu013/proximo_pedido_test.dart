import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';

/// CU-013: el chofer por terminar su entrega puede aceptar UN pedido más, que
/// queda en espera y se le muestra como «Tu próximo pedido» al terminar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDialogService dialogs;
  late MockDriverSocketService socket;
  late MockDriverAuthService auth;
  late MockDriverApiService driverApi;
  late MockApiClient api;
  late StreamController<Map<String, dynamic>> offers;
  late StreamController<Map<String, dynamic>> cancelled;

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
        .thenAnswer((_) async =>
            DialogResponse(confirmed: true, data: {'map': 'stay'}));
  });

  /// Espera hasta que se cumpla [cond] (máx. 5 s): no depende de márgenes fijos.
  Future<void> hasta(bool Function() cond) async {
    for (var i = 0; i < 250 && !cond(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  final vms = <HomeViewModel>[];
  HomeViewModel nuevo(MockApiClient? cliente) {
    final m = cliente == null
        ? HomeViewModel(trips: trips)
        : HomeViewModel(trips: trips, apiClient: cliente);
    vms.add(m);
    return m;
  }

  tearDown(() async {
    for (final m in vms) {
      try {
        m.dispose();
      } catch (_) {
        // StreamViewModel.dispose falla si nunca se inicializó el stream.
      }
    }
    vms.clear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await offers.close();
    await cancelled.close();
    NavigationLauncher.launcher = null;
    locator.reset();
  });

  Future<HomeViewModel> conectado() async {
    api = MockApiClient();
    when(api.patch(any, any, any)).thenAnswer(
        (_) async => Response(requestOptions: RequestOptions(path: '')));
    final m = nuevo(api);
    await m.connect();
    return m;
  }

  Future<void> llega(String id) async {
    offers.add({'orderId': id, 'event': 'NEW_ORDER'});
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  DriverOrder pedido(String id, DriverOrderStatus s) => DriverOrder(
      id: id,
      status: s,
      total: 1,
      createdAt: DateTime(2026, 11, 2),
      customerName: 'Prueba Dos',
      address: 'Calle 1');

  void enCamino() => when(driverApi.activeOrder())
      .thenAnswer((_) async => pedido('oA', DriverOrderStatus.onTheWay));

  group('oferta con una entrega en curso', () {
    test('se muestra y, al aceptarla, queda en espera sin abrir otra pantalla',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = await conectado();
      await llega('oB');
      verify(trips.setStatus('oB', 'accepted')).called(1);
      verifyNever(trips.reject('oB'));
      verifyNever(nav.navigateToDeliveryView(orderId: 'oB'));
      verifyNever(socket.startBroadcasting('oB', any, any));
      expect(m.queuedOrderId, 'oB');
      verify(dialogs.showDialog(
              title: 'Tu próximo pedido', description: anyNamed('description')))
          .called(1);
    });

    test('con uno ya en espera, la siguiente se rechaza: nunca dos encolados',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = await conectado();
      await llega('oB');
      await llega('oC');
      verify(trips.reject('oC')).called(1);
      verifyNever(trips.setStatus('oC', 'accepted'));
      expect(m.queuedOrderId, 'oB');
    });

    test('rechazarla desde el diálogo no deja nada en espera', () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async => DialogResponse(confirmed: false));
      final m = await conectado();
      await llega('oB');
      verify(trips.reject('oB')).called(1);
      expect(m.queuedOrderId, isNull);
    });

    test('si el back rechaza aceptarla, no queda en espera', () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      when(trips.setStatus('oB', 'accepted')).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          response: Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 409,
              data: {'message': 'Ya tenés un pedido aceptado esperando'})));
      final m = await conectado();
      await llega('oB');
      expect(m.queuedOrderId, isNull);
    });
  });

  group('al terminar la entrega actual', () {
    test(
        'el pedido en espera se anuncia como «Tu próximo pedido» y sigue el circuito',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = await conectado();
      await llega('oB');
      clearInteractions(dialogs);

      when(trips.activeOrderId).thenReturn(null);
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oB', DriverOrderStatus.accepted));
      await m.resumeActiveOrder(except: 'oA', collect: false);

      verify(dialogs.showDialog(
              title: 'Tu próximo pedido',
              description: argThat(contains('Prueba Dos · Calle 1'),
                  named: 'description')))
          .called(1);
      verify(nav.navigateToDeliveryView(orderId: 'oB')).called(1);
      expect(m.queuedOrderId, isNull);
    });

    test(
        'A entregado con el cobro en «Más tarde»: se abre B y el chofer sigue en línea',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = await conectado();
      await llega('oB');

      // Termina A (el cobro queda pendiente): el back devuelve primero el
      // aceptado que espera.
      when(trips.activeOrderId).thenReturn(null);
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oB', DriverOrderStatus.accepted));
      await m.resumeActiveOrder(except: 'oA', collect: false);
      m.syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(nav.navigateToDeliveryView(orderId: 'oB')).called(1);
      verifyNever(api.patch(
          'delivery/user/u1/availability', {'available': false}, 'tok'));
    });

    test('si la consulta falla, el pedido en espera se conserva', () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = await conectado();
      await llega('oB');
      when(trips.activeOrderId).thenReturn(null);
      when(driverApi.activeOrder()).thenThrow(Exception('sin red'));
      await m.resumeActiveOrder(except: 'oA', collect: false);
      expect(m.queuedOrderId, 'oB');
      verifyNever(nav.navigateToDeliveryView(orderId: 'oB'));

      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oB', DriverOrderStatus.accepted));
      await m.resumeActiveOrder(except: 'oA', collect: false);
      verify(nav.navigateToDeliveryView(orderId: 'oB')).called(1);
      expect(m.queuedOrderId, isNull);
    });

    test('un pedido que no era el aceptado en espera se retoma sin el anuncio',
        () async {
      final m = nuevo(null);
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oX', DriverOrderStatus.accepted));
      await m.resumeActiveOrder(except: 'oA', collect: false);
      verifyNever(dialogs.showDialog(
          title: 'Tu próximo pedido', description: anyNamed('description')));
      verify(nav.navigateToDeliveryView(orderId: 'oX')).called(1);
    });
  });

  test(
      'con la entrega actual apenas aceptada (no en camino), la oferta se rechaza',
      () async {
    when(trips.activeOrderId).thenReturn('oA');
    when(driverApi.activeOrder())
        .thenAnswer((_) async => pedido('oA', DriverOrderStatus.accepted));
    final m = await conectado();
    await llega('oB');
    verify(trips.reject('oB')).called(1);
    verifyNever(trips.setStatus('oB', 'accepted'));
    expect(m.queuedOrderId, isNull);
  });

  test('si no se puede averiguar el pedido en curso, la oferta se rechaza',
      () async {
    when(trips.activeOrderId).thenReturn('oA');
    when(driverApi.activeOrder()).thenThrow(Exception('sin red'));
    final m = await conectado();
    await llega('oB');
    verify(trips.reject('oB')).called(1);
    expect(m.queuedOrderId, isNull);
  });

  group('el pedido en espera se cancela', () {
    test('se limpia la marca, se avisa y vuelven a llegar ofertas', () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = await conectado();
      await llega('oB');
      expect(m.queuedOrderId, 'oB');
      clearInteractions(dialogs);

      cancelled.add({'orderId': 'oB'});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(m.queuedOrderId, isNull);
      verify(dialogs.showDialog(
              title: 'Tu próximo pedido',
              description: 'Tu próximo pedido ya no está asignado a vos.'))
          .called(1);

      await llega('oC');
      verify(trips.setStatus('oC', 'accepted')).called(1);
      expect(m.queuedOrderId, 'oC');
    });

    test('la cancelación de otro pedido no toca al que espera', () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = await conectado();
      await llega('oB');
      cancelled.add({'orderId': 'oA'});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(m.queuedOrderId, 'oB');
    });
  });

  group('el diálogo se cierra solo (termina la entrega en curso)', () {
    void sinRespuesta() => when(dialogs.showCustomDialog(
            variant: anyNamed('variant'),
            data: anyNamed('data'),
            barrierDismissible: anyNamed('barrierDismissible')))
        .thenAnswer((_) async => null);

    test('si ya estaba aceptada en el back, queda en espera y no se rechaza',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      sinRespuesta();
      when(trips.order('oB'))
          .thenAnswer((_) async => trip(status: 'accepted', deliveryId: 'd1'));
      final m = await conectado();
      await llega('oB');
      verifyNever(trips.reject('oB'));
      expect(m.queuedOrderId, 'oB');
    });

    test('si la oferta sigue vigente, se vuelve a mostrar sin rechazarla',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      sinRespuesta();
      when(trips.order('oB')).thenAnswer((_) async => trip(status: 'pending'));
      await conectado();
      offers.add({
        'orderId': 'oB',
        'expiresAt':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      verifyNever(trips.reject('oB'));
      verify(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .called(2);
    });

    test('si la oferta ya venció, no se rechaza ni se vuelve a mostrar',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      sinRespuesta();
      when(trips.order('oB')).thenAnswer((_) async => trip(status: 'pending'));
      await conectado();
      offers.add({
        'orderId': 'oB',
        'expiresAt': DateTime.now()
            .subtract(const Duration(seconds: 5))
            .toIso8601String(),
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      verifyNever(trips.reject('oB'));
      verify(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .called(1);
    });
  });

  test('dos ofertas casi juntas: una sola se muestra, la otra se rechaza',
      () async {
    when(trips.activeOrderId).thenReturn('oA');
    final gate = Completer<DriverOrder?>();
    when(driverApi.activeOrder()).thenAnswer((_) => gate.future);
    await conectado();
    offers.add({'orderId': 'oB'});
    offers.add({'orderId': 'oC'});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verify(trips.reject('oC')).called(1);
    gate.complete(pedido('oA', DriverOrderStatus.onTheWay));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    verify(trips.setStatus('oB', 'accepted')).called(1);
    verifyNever(trips.setStatus('oC', 'accepted'));
    verifyNever(trips.reject('oB'));
  });

  test(
      'si la entrega en curso termina mientras se consulta, la oferta se rechaza y la retoma se programa igual',
      () async {
    when(trips.activeOrderId).thenReturn('oA');
    final consulta = Completer<DriverOrder?>();
    var llamadas = 0;
    when(driverApi.activeOrder()).thenAnswer((_) {
      llamadas++;
      return llamadas == 1
          ? consulta.future
          : Future.value(pedido('oX', DriverOrderStatus.accepted));
    });
    final fin = Completer<void>();
    when(trips.waitFlow()).thenAnswer((_) => fin.future);
    final m = await conectado();
    unawaited(m.acceptOrder('oA'));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    offers.add({'orderId': 'oB'});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // A termina con la consulta todavía en vuelo.
    when(trips.activeOrderId).thenReturn(null);
    fin.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    consulta.complete(pedido('oA', DriverOrderStatus.accepted));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    verify(trips.reject('oB')).called(1);
    verify(nav.navigateToDeliveryView(orderId: 'oX')).called(1);
  });

  test(
      'flujo real: A aceptada por el diálogo y en curso; la oferta B llega durante la entrega, se muestra y no se rechaza',
      () async {
    // El pedido A entró por una oferta: el flujo de la entrega queda pendiente.
    final entregaDeA = Completer<void>();
    when(trips.waitFlow()).thenAnswer((_) => entregaDeA.future);
    when(trips.activeOrderId).thenReturn(null);
    var ofertasMostradas = 0;
    when(dialogs.showCustomDialog(
            variant: anyNamed('variant'),
            data: anyNamed('data'),
            barrierDismissible: anyNamed('barrierDismissible')))
        .thenAnswer((_) async {
      ofertasMostradas++;
      return DialogResponse(confirmed: true, data: {'map': 'stay'});
    });
    final m = await conectado();

    await llega('oA');
    verify(trips.setStatus('oA', 'accepted')).called(1);
    verify(nav.navigateToDeliveryView(orderId: 'oA')).called(1);

    // A sigue en curso y va en camino.
    when(trips.activeOrderId).thenReturn('oA');
    enCamino();
    await llega('oB');

    expect(ofertasMostradas, 2);
    verifyNever(trips.reject('oB'));
    verify(trips.setStatus('oB', 'accepted')).called(1);
    expect(m.queuedOrderId, 'oB');
    entregaDeA.complete();
  });

  test('flujo real: dos ofertas casi juntas durante la entrega, una sola entra',
      () async {
    final entregaDeA = Completer<void>();
    when(trips.waitFlow()).thenAnswer((_) => entregaDeA.future);
    when(trips.activeOrderId).thenReturn(null);
    await conectado();
    await llega('oA');

    when(trips.activeOrderId).thenReturn('oA');
    final gate = Completer<DriverOrder?>();
    when(driverApi.activeOrder()).thenAnswer((_) => gate.future);
    offers.add({'orderId': 'oB'});
    offers.add({'orderId': 'oC'});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verify(trips.reject('oC')).called(1);
    gate.complete(pedido('oA', DriverOrderStatus.onTheWay));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    verify(trips.setStatus('oB', 'accepted')).called(1);
    verifyNever(trips.reject('oB'));
    entregaDeA.complete();
  });

  group('al abrir la app', () {
    HomeViewModel abrir() {
      api = MockApiClient();
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      return nuevo(api);
    }

    test('con un pedido en curso conecta el socket (el back lo tiene en línea)',
        () async {
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oA', DriverOrderStatus.onTheWay));
      abrir().syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(socket.connect('tok', 'u1')).called(1);
      verifyNever(api.patch(
          'delivery/user/u1/availability', {'available': false}, 'tok'));
    });

    test('con un flujo ya abierto en memoria también conecta', () async {
      when(trips.activeOrderId).thenReturn('oA');
      abrir().syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(socket.connect('tok', 'u1')).called(1);
    });

    test(
        'si el socket no conecta con un pedido en curso, no se lo baja ni se corta',
        () async {
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => false);
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oA', DriverOrderStatus.onTheWay));
      abrir().syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(socket.connect('tok', 'u1')).called(1);
      verifyNever(api.patch(
          'delivery/user/u1/availability', {'available': false}, 'tok'));
      verifyNever(socket.disconnect());
      verifyNever(dialogs.showDialog(
          title: 'No pudimos ponerte en línea',
          description: anyNamed('description')));
    });

    test('con un flujo en memoria y el socket caído tampoco se lo baja',
        () async {
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => false);
      when(trips.activeOrderId).thenReturn('oA');
      abrir().syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(api.patch(
          'delivery/user/u1/availability', {'available': false}, 'tok'));
    });

    test('sin pedido en curso, si no conecta, sí queda fuera de línea',
        () async {
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => false);
      final m = abrir();
      await m.connect();
      verify(api.patch(
              'delivery/user/u1/availability', {'available': false}, 'tok'))
          .called(1);
    });

    test('fuera de línea y sin pedido: lo baja y no conecta', () async {
      when(driverApi.activeOrder()).thenAnswer((_) async => null);
      abrir().syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(socket.connect(any, any));
      verify(api.patch(
              'delivery/user/u1/availability', {'available': false}, 'tok'))
          .called(1);
    });
  });

  group('socket que falla en plena entrega', () {
    test('si después reconecta solo, las ofertas llegan y se muestran',
        () async {
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => false);
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final api2 = MockApiClient();
      when(api2.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      nuevo(api2).syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(socket.connect('tok', 'u1')).called(1);

      await llega('oB');
      verify(trips.setStatus('oB', 'accepted')).called(1);
      verifyNever(trips.reject('oB'));
    });
  });

  group('ronda 8', () {
    MockApiClient apiQueFalla({bool alDisponible = true}) {
      final a = MockApiClient();
      when(a.patch(any, any, any)).thenAnswer((inv) async {
        final cuerpo = inv.positionalArguments[1];
        if (alDisponible && cuerpo is Map && cuerpo['available'] == true) {
          throw DioException(requestOptions: RequestOptions(path: ''));
        }
        return Response(requestOptions: RequestOptions(path: ''));
      });
      return a;
    }

    test(
        'B1-bis: si falla un paso previo al socket en plena entrega, las ofertas igual se escuchan',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      nuevo(apiQueFalla()).syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(socket.connect(any, any)); // el PATCH falló antes del socket

      await llega('oB');
      verify(trips.setStatus('oB', 'accepted')).called(1);
      verifyNever(trips.reject('oB'));
    });

    test(
        'S-a: el reintento programado no corre si cerró sesión, y se corta el socket',
        () async {
      var intentos = 0;
      when(nav.navigateToDeliveryView(orderId: 'oA')).thenAnswer((_) async {
        if (++intentos == 1) throw Exception('sin navegación');
        return null;
      });
      when(trips.activeOrderId).thenReturn(null);
      final m = await conectado();
      m.flowRetryDelay = const Duration(milliseconds: 600);
      await llega('oA');
      clearInteractions(driverApi);
      await m.logout();
      verify(socket.stopBroadcasting()).called(1);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      verifyNever(driverApi.activeOrder());
      expect(intentos, 1);
    });

    test('S-a: si cierra sesión mientras la retoma consulta, no abre nada',
        () async {
      final gate = Completer<DriverOrder?>();
      when(driverApi.activeOrder()).thenAnswer((_) => gate.future);
      final m = nuevo(null);
      final retoma = m.resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await m.logout();
      gate.complete(pedido('oA', DriverOrderStatus.accepted));
      await retoma;
      verifyNever(nav.navigateToDeliveryView(orderId: 'oA'));
    });

    test('S-b: si la retoma también falla, no deja el pedido activo pegado',
        () async {
      var yaAceptado = false;
      when(driverApi.activeOrder()).thenAnswer((_) async =>
          yaAceptado ? pedido('oA', DriverOrderStatus.accepted) : null);
      when(trips.setStatus('oA', 'accepted')).thenAnswer((_) async {
        yaAceptado = true;
      });
      when(nav.navigateToDeliveryView(orderId: 'oA'))
          .thenThrow(Exception('sin navegación'));
      when(trips.activeOrderId).thenReturn(null);
      final m = await conectado();
      m.flowRetryDelay = const Duration(milliseconds: 20);
      await llega('oA');
      await hasta(() => false);
    });

    test(
        'S-c: mientras espera el reintento, una oferta nueva se rechaza por ocupado',
        () async {
      var intentos = 0;
      var yaAceptado = false;
      when(nav.navigateToDeliveryView(orderId: 'oA')).thenAnswer((_) async {
        if (++intentos == 1) throw Exception('sin navegación');
        return null;
      });
      when(driverApi.activeOrder()).thenAnswer((_) async =>
          yaAceptado ? pedido('oA', DriverOrderStatus.accepted) : null);
      when(trips.setStatus('oA', 'accepted')).thenAnswer((_) async {
        yaAceptado = true;
      });
      when(trips.activeOrderId).thenReturn(null);
      final m = await conectado();
      m.flowRetryDelay = const Duration(milliseconds: 600);
      await llega('oA');
      await llega('oC');
      verify(trips.reject('oC')).called(1);
      verifyNever(trips.setStatus('oC', 'accepted'));
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      verify(nav.navigateToDeliveryView(orderId: 'oA')).called(2);
    });

    test('S-e: si el connect MANUAL falla en entrega, se avisa y no se baja',
        () async {
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => false);
      when(trips.activeOrderId).thenReturn('oA');
      final a = apiQueFalla(alDisponible: false);
      final m = nuevo(a);
      await m.connect();
      verify(dialogs.showDialog(
              title: 'No pudimos ponerte en línea',
              description: anyNamed('description')))
          .called(1);
      verifyNever(a.patch(
          'delivery/user/u1/availability', {'available': false}, 'tok'));
    });
  });

  group('ronda 9', () {
    test('B: volver a primer plano durante el logout no reconecta al que se va',
        () async {
      final bajada = Completer<Response<dynamic>>();
      final a = MockApiClient();
      when(a.patch(any, any, any)).thenAnswer((inv) {
        final cuerpo = inv.positionalArguments[1];
        if (cuerpo is Map && cuerpo['available'] == false) {
          return bajada.future;
        }
        return Future.value(Response(requestOptions: RequestOptions(path: '')));
      });
      when(trips.activeOrderId).thenReturn('oA');
      when(socket.isConnected).thenReturn(false);
      final m = nuevo(a);
      final salida = m.logout();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(socket.connect(any, any));
      verifyNever(
          a.patch('delivery/user/u1/availability', {'available': true}, 'tok'));
      bajada.complete(Response(requestOptions: RequestOptions(path: '')));
      await salida;
    });

    test(
        'A: una entrega que reabre el socket sin estar «en línea» completa el armado al terminar',
        () async {
      final board = locator<MaintenanceBoard>() as MockMaintenanceBoard;
      final notifier =
          locator<MaintenanceNotifier>() as MockMaintenanceNotifier;
      when(notifier.pending).thenReturn(const []);
      final a = MockApiClient();
      when(a.patch(any, any, any)).thenAnswer((inv) async {
        final cuerpo = inv.positionalArguments[1];
        if (cuerpo is Map && cuerpo['available'] == true) {
          throw DioException(requestOptions: RequestOptions(path: ''));
        }
        return Response(requestOptions: RequestOptions(path: ''));
      });
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = nuevo(a);
      m.syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(board.attach(any)); // el armado no se hizo

      // La entrega abre el socket por su cuenta y después termina.
      when(trips.activeOrderId).thenReturn(null);
      when(socket.hasSocket).thenReturn(true);
      when(socket.isConnected).thenReturn(true);
      final fin = Completer<void>();
      when(trips.waitFlow()).thenAnswer((_) => fin.future);
      final retoma = m.resumeActiveOrder();
      await hasta(() => false == (fin.isCompleted) && vms.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      fin.complete();
      await retoma;
      await hasta(() {
        try {
          verify(board.attach(any));
          return true;
        } catch (_) {
          return false;
        }
      });
      verify(notifier.start()).called(1);
    });

    test(
        'C: si la retoma falla al abrir la entrega, se reintenta y al tope se avisa',
        () async {
      when(nav.navigateToDeliveryView(orderId: 'oA'))
          .thenThrow(Exception('sin navegación'));
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oA', DriverOrderStatus.accepted));
      when(trips.activeOrderId).thenReturn(null);
      final m = nuevo(null);
      m.flowRetryDelay = const Duration(milliseconds: 20);
      await m.resumeActiveOrder();
      await hasta(() {
        try {
          verify(dialogs.showDialog(
              title: 'No pudimos abrir tu entrega',
              description: anyNamed('description')));
          return true;
        } catch (_) {
          return false;
        }
      });
      // El arranque y tres reintentos; después el aviso, sin más intentos.
      verify(nav.navigateToDeliveryView(orderId: 'oA')).called(4);
      verify(trips.endFlow()).called(4);
    });

    test('D: si el cobro no se puede abrir, no queda el pedido activo pegado',
        () async {
      when(nav.navigateToPaymentView(orderId: 'oA'))
          .thenThrow(Exception('sin navegación'));
      when(driverApi.activeOrder()).thenAnswer((_) async => DriverOrder(
            id: 'oA',
            status: DriverOrderStatus.delivered,
            total: 1,
            createdAt: DateTime.now(),
            deliveredAt: DateTime.now(),
            paymentMethod: 'cash',
            paymentStatus: 'pending',
          ));
      when(trips.activeOrderId).thenReturn(null);
      await nuevo(null).resumeActiveOrder();
      verify(trips.endFlow()).called(1);
    });

    test('el cierre de sesión no se saltea pasos si uno falla', () async {
      when(socket.stopBroadcasting()).thenThrow(Exception('socket'));
      final m = nuevo(null);
      await m.logout();
      verify(auth.signOut()).called(1);
    });
  });

  group('ronda 10', () {
    test(
        '1: volver a primer plano durante el logout no retoma ni abre la entrega',
        () async {
      final bajada = Completer<Response<dynamic>>();
      final a = MockApiClient();
      when(a.patch(any, any, any)).thenAnswer((inv) {
        final cuerpo = inv.positionalArguments[1];
        if (cuerpo is Map && cuerpo['available'] == false) {
          return bajada.future;
        }
        return Future.value(Response(requestOptions: RequestOptions(path: '')));
      });
      when(trips.activeOrderId).thenReturn(null);
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oA', DriverOrderStatus.accepted));
      final m = nuevo(a);
      final salida = m.logout();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(socket.startBroadcasting(any, any, any));
      verifyNever(nav.navigateToDeliveryView(orderId: 'oA'));
      bajada.complete(Response(requestOptions: RequestOptions(path: '')));
      await salida;
    });

    test('2: un error de red al consultar durante el reintento reprograma',
        () async {
      var consultas = 0;
      var navegaciones = 0;
      when(nav.navigateToDeliveryView(orderId: 'oA')).thenAnswer((_) async {
        if (++navegaciones == 1) throw Exception('sin navegación');
        return null;
      });
      var yaAceptado = false;
      when(trips.setStatus('oA', 'accepted')).thenAnswer((_) async {
        yaAceptado = true;
      });
      when(driverApi.activeOrder()).thenAnswer((_) async {
        if (!yaAceptado) return null;
        if (++consultas == 1) throw Exception('sin red');
        return pedido('oA', DriverOrderStatus.accepted);
      });
      when(trips.activeOrderId).thenReturn(null);
      final m = await conectado();
      m.flowRetryDelay = const Duration(milliseconds: 20);
      await llega('oA');
      await hasta(() => navegaciones >= 2);
      expect(navegaciones, 2);
      expect(consultas, greaterThanOrEqualTo(2));
    });

    test(
        '2: la cadena de reintentos termina y la siguiente tiene todos los intentos',
        () async {
      when(nav.navigateToDeliveryView(orderId: 'oA'))
          .thenThrow(Exception('sin navegación'));
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oA', DriverOrderStatus.accepted));
      when(trips.activeOrderId).thenReturn(null);
      final m = nuevo(null);
      m.flowRetryDelay = const Duration(milliseconds: 20);
      Future<void> cadena() async {
        await m.resumeActiveOrder();
        await hasta(() {
          try {
            verify(dialogs.showDialog(
                title: 'No pudimos abrir tu entrega',
                description: anyNamed('description')));
            return true;
          } catch (_) {
            return false;
          }
        });
      }

      await cadena();
      await cadena();
      // Dos cadenas completas: 4 intentos cada una.
      verify(nav.navigateToDeliveryView(orderId: 'oA')).called(8);
    });

    test('3: un error al cerrar la entrega no dispara un reintento', () async {
      final fg =
          locator<DriverForegroundService>() as MockDriverForegroundService;
      when(fg.update(title: 'Estás en línea', text: anyNamed('text')))
          .thenThrow(Exception('servicio'));
      var terminada = false;
      when(trips.waitFlow()).thenAnswer((_) async {
        terminada = true;
      });
      when(driverApi.activeOrder()).thenAnswer((_) async =>
          terminada ? null : pedido('oA', DriverOrderStatus.accepted));
      when(trips.activeOrderId).thenReturn(null);
      final m = nuevo(null);
      m.flowRetryDelay = const Duration(milliseconds: 20);
      await m.resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      verify(nav.navigateToDeliveryView(orderId: 'oA')).called(1);
      verifyNever(trips.endFlow());
    });
  });

  group('cierre de sesión y desconexión manual', () {
    test('si cierra sesión mientras la apertura consulta, no se reconecta',
        () async {
      final gate = Completer<DriverOrder?>();
      when(driverApi.activeOrder()).thenAnswer((_) => gate.future);
      api = MockApiClient();
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      final m = nuevo(api);
      m.syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await m.logout();
      gate.complete(pedido('oA', DriverOrderStatus.onTheWay));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(socket.connect(any, any));
    });

    test(
        'si cierra sesión y la consulta no encuentra pedido, no se repite la baja',
        () async {
      final gate = Completer<DriverOrder?>();
      when(driverApi.activeOrder()).thenAnswer((_) => gate.future);
      api = MockApiClient();
      when(api.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      final m = nuevo(api);
      m.syncAvailabilityOnOpenForTest();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await m.logout();
      final bajasAntes = verify(api.patch(
              'delivery/user/u1/availability', {'available': false}, 'tok'))
          .callCount;
      gate.complete(null);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(api.patch(
          'delivery/user/u1/availability', {'available': false}, 'tok'));
      expect(bajasAntes, greaterThanOrEqualTo(1));
    });

    test('al volver a primer plano en entrega sin socket, reintenta conectar',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      when(socket.isConnected).thenReturn(false);
      final m = await conectado();
      clearInteractions(socket);
      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(socket.connect('tok', 'u1')).called(1);
    });

    test('si se desconectó a mano, no se lo reconecta solo', () async {
      when(trips.activeOrderId).thenReturn('oA');
      when(socket.isConnected).thenReturn(false);
      final m = await conectado();
      await m.disconnect();
      clearInteractions(socket);
      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(socket.connect(any, any));
    });
  });

  group('el próximo pedido se anuncia', () {
    test('una oferta durante el anuncio se rechaza y queda un único flujo',
        () async {
      when(trips.activeOrderId).thenReturn('oA');
      enCamino();
      final m = await conectado();
      await llega('oB');
      expect(m.queuedOrderId, 'oB');

      // Termina A: el anuncio queda esperando al chofer.
      final anuncio = Completer<void>();
      when(trips.activeOrderId).thenReturn(null);
      when(driverApi.activeOrder())
          .thenAnswer((_) async => pedido('oB', DriverOrderStatus.accepted));
      when(dialogs.showDialog(
              title: 'Tu próximo pedido', description: anyNamed('description')))
          .thenAnswer((_) => anuncio.future.then((_) => null));
      clearInteractions(dialogs);
      final retoma = m.resumeActiveOrder(except: 'oA', collect: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await llega('oC');
      verify(trips.reject('oC')).called(1);
      verifyNever(trips.setStatus('oC', 'accepted'));
      verifyNever(nav.navigateToDeliveryView(orderId: 'oC'));

      anuncio.complete();
      await retoma;
      verify(trips.beginFlow('oB')).called(greaterThanOrEqualTo(1));
      verify(nav.navigateToDeliveryView(orderId: 'oB')).called(1);
    });
  });

  test(
      'con el estado real del flujo: durante el anuncio la oferta C se rechaza sin consultar y B se abre una vez',
      () async {
    String? activo = 'oA';
    when(trips.activeOrderId).thenAnswer((_) => activo);
    when(trips.beginFlow(any)).thenAnswer((i) {
      activo = i.positionalArguments.first as String;
    });
    when(trips.endFlow()).thenAnswer((_) {
      activo = null;
    });
    enCamino();
    final m = await conectado();
    await llega('oB');
    expect(m.queuedOrderId, 'oB');

    activo = null; // termina A
    final anuncio = Completer<void>();
    when(dialogs.showDialog(
            title: 'Tu próximo pedido', description: anyNamed('description')))
        .thenAnswer((_) => anuncio.future.then((_) => null));
    when(driverApi.activeOrder())
        .thenAnswer((_) async => pedido('oB', DriverOrderStatus.accepted));
    clearInteractions(driverApi);
    final retoma = m.resumeActiveOrder(except: 'oA', collect: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(activo, 'oB');

    await llega('oC');
    verify(trips.reject('oC')).called(1);
    verify(driverApi.activeOrder()).called(1);

    anuncio.complete();
    await retoma;
    verify(nav.navigateToDeliveryView(orderId: 'oB')).called(1);
    verifyNever(trips.endFlow());
  });

  group('la oferta aceptada', () {
    test(
        'si falla abrir la entrega no se rechaza el pedido, se suelta el flujo y se reintenta la retoma',
        () async {
      var intentos = 0;
      when(nav.navigateToDeliveryView(orderId: 'oA')).thenAnswer((_) async {
        if (++intentos == 1) throw Exception('sin navegación');
        return null;
      });
      var yaAceptado = false;
      when(driverApi.activeOrder()).thenAnswer((_) async =>
          yaAceptado ? pedido('oA', DriverOrderStatus.accepted) : null);
      when(trips.setStatus('oA', 'accepted')).thenAnswer((_) async {
        yaAceptado = true;
      });
      when(trips.activeOrderId).thenReturn(null);
      final m = await conectado();
      m.flowRetryDelay = const Duration(milliseconds: 20);
      await llega('oA');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      verifyNever(trips.reject('oA'));
      verify(trips.setStatus('oA', 'accepted')).called(1);
      verify(trips.endFlow()).called(1);
      expect(intentos, 2);
    });

    test(
        'al arrancar la entrega no se pasan los avisos de taller antes del fin',
        () async {
      final notifier =
          locator<MaintenanceNotifier>() as MockMaintenanceNotifier;
      when(notifier.pending).thenReturn(const []);
      when(trips.activeOrderId).thenReturn(null);
      await conectado();
      await llega('oA');
      verify(notifier.offerEnded(pump: false)).called(1);
      verifyNever(notifier.offerEnded(pump: true));
    });
  });

  test('sin entrega en curso la oferta se acepta como siempre', () async {
    when(trips.activeOrderId).thenReturn(null);
    final m = await conectado();
    await llega('oB');
    verify(trips.setStatus('oB', 'accepted')).called(1);
    verify(nav.navigateToDeliveryView(orderId: 'oB')).called(1);
    expect(m.queuedOrderId, isNull);
  });
}
