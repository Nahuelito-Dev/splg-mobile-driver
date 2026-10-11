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
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_lib/permissions/app_permission.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeViewmodelTest -', () {
    late MockDriverAuthService auth;
    late MockNavigationService navigation;
    late MockDriverSocketService socket;
    late MockDriverForegroundService foreground;
    late MockDialogService dialogs;
    late MockLocationService location;
    late MockApiClient api;

    const availabilityPath = 'delivery/user/u1/availability';

    setUp(() {
      registerServices();
      auth = locator<DriverAuthService>() as MockDriverAuthService;
      navigation = locator<NavigationService>() as MockNavigationService;
      socket = locator<DriverSocketService>() as MockDriverSocketService;
      foreground =
          locator<DriverForegroundService>() as MockDriverForegroundService;
      dialogs = locator<DialogService>() as MockDialogService;
      location = locator<LocationService>() as MockLocationService;
      api = MockApiClient();

      when(auth.token).thenAnswer((_) async => 'tok');
      when(auth.userId).thenReturn('u1');
      when(socket.isConnected).thenReturn(false);
      when(socket.hasSocket).thenReturn(false);
      when(api.patch(any, any, any)).thenAnswer(
        (_) async => Response(requestOptions: RequestOptions(path: '')),
      );
    });
    tearDown(() => locator.reset());

    HomeViewModel build() => HomeViewModel(apiClient: api);

    group('logout -', () {
      test('cierra la sesión de verdad y vuelve al login', () async {
        await build().logout();

        verify(auth.signOut()).called(1);
        verify(navigation.clearStackAndShow(Routes.loginView)).called(1);
      });

      test(
          'tras reabrir la app (sin estado en memoria) igual baja la '
          'disponibilidad', () async {
        // Estado limpio: nunca hubo connect en esta sesión de la app.
        await build().logout();

        verifyInOrder([
          api.patch(availabilityPath, {'available': false}, 'tok'),
          auth.signOut(),
        ]);
      });

      test('si el PATCH falla, igual cierra la sesión', () async {
        when(api.patch(any, any, any))
            .thenThrow(DioException(requestOptions: RequestOptions(path: '')));

        await build().logout();

        verify(auth.signOut()).called(1);
        verify(navigation.clearStackAndShow(Routes.loginView)).called(1);
      });

      test(
          'carrera: si se cierra sesión con connect en vuelo, connect aborta '
          'y la disponibilidad termina en false', () async {
        final trueAnswer = Completer<Response>();
        final sent = <bool>[];
        when(api.patch(any, any, any)).thenAnswer((inv) {
          final available =
              (inv.positionalArguments[1] as Map)['available'] as bool;
          sent.add(available);
          return available
              ? trueAnswer.future
              : Future.value(
                  Response(requestOptions: RequestOptions(path: '')));
        });
        when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
        final model = build();

        final connecting = model.connect();
        await Future<void>.delayed(Duration.zero);
        final loggingOut = model.logout();
        // El PATCH "true" todavía no volvió: logout no puede haber firmado afuera.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        verifyNever(auth.signOut());

        trueAnswer.complete(Response(requestOptions: RequestOptions(path: '')));
        await connecting;
        await loggingOut;

        expect(sent.last, isFalse);
        expect(sent.first, isTrue);
        verifyNever(socket.connect(any, any));
        verifyNever(
            foreground.start(title: anyNamed('title'), text: anyNamed('text')));
        verifyNever(dialogs.showDialog(
            title: 'No pudimos ponerte en línea',
            description: anyNamed('description')));
        expect(model.isOnline, isFalse);
        verify(auth.signOut()).called(1);
        verify(navigation.clearStackAndShow(Routes.loginView)).called(1);
      });

      test('con el socket conectado se baja del radar antes de salir',
          () async {
        when(socket.isConnected).thenReturn(true);
        when(socket.hasSocket).thenReturn(true);

        await build().logout();

        verify(api.patch(availabilityPath, {'available': false}, 'tok'))
            .called(1);
        verify(foreground.stop()).called(1);
        verify(socket.disconnect()).called(1);
        verify(auth.signOut()).called(1);
      });

      test('con la red caída (socket caído pero existente) también se baja',
          () async {
        // isConnected false (se cayó), pero el socket sigue y reconectaría.
        when(socket.hasSocket).thenReturn(true);

        await build().logout();

        verify(api.patch(availabilityPath, {'available': false}, 'tok'))
            .called(1);
        verify(socket.disconnect()).called(1);
        verify(foreground.stop()).called(1);
      });

      test('si el PATCH se cuelga no deja la pantalla trabada', () async {
        when(socket.hasSocket).thenReturn(true);
        when(api.patch(any, any, any))
            .thenAnswer((_) => Completer<Response>().future);

        await build().logout().timeout(
              const Duration(seconds: 8),
              onTimeout: () => fail('logout quedó esperando al PATCH'),
            );

        verify(auth.signOut()).called(1);
        verify(navigation.clearStackAndShow(Routes.loginView)).called(1);
      });
    });

    group('connect -', () {
      test('si el socket no conecta, revierte la disponibilidad y avisa',
          () async {
        when(socket.waitUntilConnected(any)).thenAnswer((_) async => false);
        final model = build();

        await model.connect();

        verifyInOrder([
          api.patch(availabilityPath, {'available': true}, 'tok'),
          api.patch(availabilityPath, {'available': false}, 'tok'),
        ]);
        verify(foreground.stop()).called(1);
        verify(socket.disconnect()).called(1);
        verify(dialogs.showDialog(
          title: 'No pudimos ponerte en línea',
          description: anyNamed('description'),
        )).called(1);
        expect(model.isOnline, isFalse);
      });

      test('si el back rechaza la disponibilidad no abre socket ni servicio',
          () async {
        when(api.patch(availabilityPath, {'available': true}, 'tok'))
            .thenThrow(DioException(requestOptions: RequestOptions(path: '')));

        await build().connect();

        verifyNever(socket.connect(any, any));
        verifyNever(
            foreground.start(title: anyNamed('title'), text: anyNamed('text')));
        verify(dialogs.showDialog(
          title: 'No pudimos ponerte en línea',
          description: anyNamed('description'),
        )).called(1);
      });

      test('conectado: queda en línea y un logout posterior lo baja', () async {
        when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
        final model = build();

        await model.connect();
        expect(model.isOnline, isTrue);
        await model.logout();

        verify(api.patch(availabilityPath, {'available': false}, 'tok'))
            .called(1);
      });
    });

    group('búsqueda de pedidos -', () {
      test(
          'al conectar busca; sin ofertas pasa a "sin pedidos"; al '
          'desconectar vuelve a idle', () async {
        when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
        final model = HomeViewModel(
            apiClient: api, searchTimeout: const Duration(milliseconds: 30));
        expect(model.search, HomeSearch.idle);

        await model.connect();
        expect(model.search, HomeSearch.searching);

        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(model.search, HomeSearch.empty);

        await model.disconnect();
        expect(model.search, HomeSearch.idle);
      });

      test('si connect falla no queda buscando', () async {
        when(socket.waitUntilConnected(any)).thenAnswer((_) async => false);
        final model = build();
        await model.connect();
        expect(model.search, HomeSearch.idle);
      });
    });

    group('estado en línea: píldora y botón coinciden -', () {
      test('fuera de línea: "Desconectado" y botón "Conectarse"', () {
        final m = build();
        expect(m.statusLabel, 'Desconectado');
        expect(m.showsDisconnect, isFalse);
      });

      test(
          'socket reconectando: sigue en línea, "Reconectando…" y botón '
          '"Desconectarse"', () {
        when(socket.hasSocket).thenReturn(true);
        when(socket.isConnected).thenReturn(false);
        final m = build();
        expect(m.statusLabel, 'Reconectando…');
        expect(m.showsDisconnect, isTrue);
      });

      test('socket conectado: "En línea" y "Desconectarse"', () {
        when(socket.hasSocket).thenReturn(true);
        when(socket.isConnected).thenReturn(true);
        final m = build();
        expect(m.statusLabel, 'En línea');
        expect(m.showsDisconnect, isTrue);
      });
    });

    group('total de hoy -', () {
      test('suma las entregas de hoy con la página más reciente', () async {
        final driverApi = locator<DriverApiService>() as MockDriverApiService;
        final today = DateTime(2026, 10, 10, 9);
        when(driverApi.ordersPage(limit: anyNamed('limit')))
            .thenAnswer((_) async => OrdersPage(total: 2, offset: 0, orders: [
                  DriverOrder(
                      id: 'a',
                      status: DriverOrderStatus.delivered,
                      total: 1500,
                      createdAt: today),
                  DriverOrder(
                      id: 'b',
                      status: DriverOrderStatus.cancelled,
                      total: 900,
                      createdAt: today),
                ]));
        final model = build()..now = () => DateTime(2026, 10, 10, 18);

        await model.loadToday();

        expect(model.todayTotal, 1500);
        expect(model.todayCount, 1);
      });

      test('si falla no muestra nada', () async {
        final driverApi = locator<DriverApiService>() as MockDriverApiService;
        when(driverApi.ordersPage(limit: anyNamed('limit')))
            .thenThrow(Exception('boom'));
        final model = build();
        await model.loadToday();
        expect(model.todayCount, 0);
      });
    });

    group('permiso de ubicación -', () {
      test('concedido: empieza el tracking', () async {
        when(location.requestLocationPermission())
            .thenAnswer((_) async => true);
        final model = build();

        await model.initialize();

        expect(model.hasLocationPermission, isTrue);
        verify(location.startTracking()).called(1);
      });

      test('denegado para siempre: muestra el estado y NO insiste', () async {
        when(location.requestLocationPermission())
            .thenAnswer((_) async => false);
        when(location.locationPermission)
            .thenReturn(PermissionOutcome.permanentlyDenied);
        final model = build();

        await model.initialize();
        model.notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(model.hasLocationPermission, isFalse);
        expect(model.permissionMessage, contains('Ajustes'));
        verify(location.requestLocationPermission()).called(1);
        verifyNever(location.startTracking());
      });

      test('al volver de Ajustes re-chequea en silencio y retoma el tracking',
          () async {
        when(location.requestLocationPermission())
            .thenAnswer((_) async => false);
        when(location.checkLocationPermission()).thenAnswer((_) async => true);
        final model = build();
        await model.initialize();

        model.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        verify(location.checkLocationPermission()).called(1);
        verify(location.requestLocationPermission()).called(1);
        expect(model.hasLocationPermission, isTrue);
        verify(location.startTracking()).called(1);
      });

      test('una caída del plugin no deja la app colgada', () async {
        when(location.requestLocationPermission())
            .thenThrow(StateError('plugin'));
        final model = build();

        await model.initialize();

        expect(model.hasLocationPermission, isFalse);
        expect(model.permissionMessage, isNotNull);
      });
    });
  });
}
