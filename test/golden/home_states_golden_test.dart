import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

/// ViewModel del Inicio con el estado que se quiere ver, sin tocar permisos,
/// GPS ni red.
class _FixedHomeModel extends HomeViewModel {
  _FixedHomeModel({HomeSearch phase = HomeSearch.idle}) {
    hasLocationPermission = true;
    search = phase;
  }

  @override
  Future<void> initialize() async {}
}

/// Mapa de reemplazo para el golden: el de Google no se renderiza en tests.
Widget _placeholderMap(BuildContext context, HomeViewModel model) => Container(
      color: const Color(0xFFE5E3DF),
      child: CustomPaint(painter: _StreetsPainter()),
    );

class _StreetsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 14;
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(Offset(0, size.height * i / 6),
          Offset(size.width, size.height * i / 6), road);
      canvas.drawLine(Offset(size.width * i / 6, 0),
          Offset(size.width * i / 6, size.height), road);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> pumpHome(WidgetTester t, HomeViewModel Function() model) async {
  t.view.physicalSize = const Size(393, 852);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  HomeView.debugMapBuilder = _placeholderMap;
  HomeView.debugViewModelFactory = model;
  addTearDown(() {
    HomeView.debugMapBuilder = null;
    HomeView.debugViewModelFactory = null;
  });
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    home: const HomeView(),
  ));
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  late MockDriverSocketService socket;

  setUp(() {
    registerServices();
    socket = locator<DriverSocketService>() as MockDriverSocketService;
  });
  tearDown(() => locator.reset());

  testGoldens('Inicio desconectado, con la hoja', (t) async {
    await loadAppFonts();
    when(socket.isConnected).thenReturn(false);
    when(socket.hasSocket).thenReturn(false);
    await pumpHome(t, () => _FixedHomeModel());
    expect(find.text('Desconectado'), findsOneWidget);
    expect(find.text('Conectarse'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_disconnected.png'));
  });

  testGoldens('Inicio en línea: "Sin pedidos disponibles"', (t) async {
    await loadAppFonts();
    when(socket.isConnected).thenReturn(true);
    when(socket.hasSocket).thenReturn(true);
    await pumpHome(t, () => _FixedHomeModel(phase: HomeSearch.empty));
    expect(find.text('En línea'), findsOneWidget);
    expect(find.text('Desconectarse'), findsOneWidget);
    expect(find.text('Sin pedidos disponibles'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_no_orders.png'));
  });

  testWidgets('socket reconectando: la píldora y el botón coinciden',
      (t) async {
    when(socket.isConnected).thenReturn(false);
    when(socket.hasSocket).thenReturn(true);
    await pumpHome(t, () => _FixedHomeModel(phase: HomeSearch.searching));
    expect(find.text('Reconectando…'), findsOneWidget);
    expect(find.text('Desconectarse'), findsOneWidget);
    expect(find.text('Conectarse'), findsNothing);
  });
}
