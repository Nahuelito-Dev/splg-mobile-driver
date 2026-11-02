import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_lib/theme/app_theme.dart';

import 'helpers/test_helpers.dart';
import 'helpers/test_helpers.mocks.dart';

void main() {
  late MockLocationService ubicacion;
  late MockDriverSocketService socket;

  setUp(() {
    registerServices();
    ubicacion = getAndRegisterLocationService();
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    when(ubicacion.checkLocationPermission()).thenAnswer((_) async => true);
    when(ubicacion.requestLocationPermission()).thenAnswer((_) async => true);
    when(socket.isConnected).thenReturn(true);
    when(socket.hasSocket).thenReturn(true);
  });
  tearDown(() {
    HomeView.debugMapBuilder = null;
    locator.reset();
  });

  group('aviso de ubicación (view model) -', () {
    test('en línea con el stream caído muestra el aviso', () async {
      when(ubicacion.locationUnavailable).thenReturn(true);
      final model = HomeViewModel()..hasLocationPermission = true;
      expect(model.showsLocationAlert, isTrue);
    });

    test('con la ubicación andando no hay aviso', () async {
      when(ubicacion.locationUnavailable).thenReturn(false);
      final model = HomeViewModel()..hasLocationPermission = true;
      expect(model.showsLocationAlert, isFalse);
    });

    test('desconectado no hay aviso aunque falle la ubicación', () async {
      when(socket.hasSocket).thenReturn(false);
      when(ubicacion.locationUnavailable).thenReturn(true);
      final model = HomeViewModel()..hasLocationPermission = true;
      expect(model.showsLocationAlert, isFalse);
    });

    test('el botón abre los ajustes que corresponden', () async {
      await HomeViewModel().openLocationAlertSettings();
      verify(ubicacion.openLocationAlertSettings()).called(1);
    });
  });

  group('aviso de ubicación (vista) -', () {
    Future<void> montar(WidgetTester tester) async {
      HomeView.debugMapBuilder = (_, __) => const SizedBox();
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const HomeView()),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('se ve con el texto y el botón, y el botón abre ajustes',
        (tester) async {
      when(ubicacion.locationUnavailable).thenReturn(true);
      await montar(tester);

      expect(find.byKey(const Key('home-location-alert')), findsOneWidget);
      expect(find.text('Activá la ubicación para recibir pedidos'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('home-location-alert-action')));
      verify(ubicacion.openLocationAlertSettings()).called(1);
    });

    testWidgets('sin falla no aparece', (tester) async {
      when(ubicacion.locationUnavailable).thenReturn(false);
      await montar(tester);

      expect(find.byKey(const Key('home-location-alert')), findsNothing);
    });

    testWidgets(
        'al reanudar con el GPS apagado sigue el mapa con el aviso, no la '
        'pantalla de bloqueo', (tester) async {
      when(ubicacion.locationUnavailable).thenReturn(false);
      await montar(tester);
      expect(find.byKey(const Key('home-location-alert')), findsNothing);

      when(ubicacion.checkLocationPermission()).thenAnswer((_) async => false);
      when(ubicacion.serviceDisabled).thenReturn(true);
      when(ubicacion.locationUnavailable).thenReturn(true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('home-location-alert')), findsOneWidget);
      expect(find.text('Desconectarse'), findsOneWidget,
          reason: 'la hoja de conexión sigue a la vista');
      expect(find.text('Conectarse'), findsNothing);
    });

    testWidgets('fuera de línea no aparece el aviso', (tester) async {
      when(socket.hasSocket).thenReturn(false);
      when(socket.isConnected).thenReturn(false);
      when(ubicacion.locationUnavailable).thenReturn(true);
      await montar(tester);

      expect(find.byKey(const Key('home-location-alert')), findsNothing);
      expect(find.text('Conectarse'), findsOneWidget);
    });
  });
}
