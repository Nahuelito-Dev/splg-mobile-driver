import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/views/change_password/change_password_view.dart';
import 'package:splg_driver/ui/views/deliveries/deliveries_view.dart';
import 'package:splg_driver/ui/views/delivery_detail/delivery_detail_view.dart';
import 'package:splg_driver/ui/views/forgot_password/forgot_password_view.dart';
import 'package:splg_driver/ui/views/help/help_view.dart';
import 'package:splg_driver/ui/views/login/login_view.dart';
import 'package:splg_driver/ui/views/notifications/notifications_view.dart';
import 'package:splg_driver/ui/views/profile/profile_view.dart';
import 'package:splg_driver/ui/views/rating/rating_view.dart';
import 'package:splg_driver/ui/views/startup/startup_view.dart';
import 'package:splg_driver/ui/views/vehicle/vehicle_view.dart';
import 'package:splg_driver/ui/views/welcome/welcome_view.dart';
import 'package:splg_driver/ui/widgets/driver_menu_drawer.dart';
import 'package:splg_lib/splg_lib.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

/// Goldens de las pantallas del chofer (393x852, 1x).
Future<void> pumpScreen(WidgetTester t, Widget home,
    {bool drawer = false}) async {
  t.view.physicalSize = const Size(393, 852);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    home: home,
  ));
  await t.pump();
  if (drawer) {
    t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  }
  // Las ilustraciones se leen del bundle (I/O real).
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      final img = e.widget as Image;
      await precacheImage(img.image, e);
    }
  });
  await t.pumpAndSettle(const Duration(milliseconds: 50));
}

Future<void> check(WidgetTester t, String name) => expectLater(
    find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

void main() {
  late MockDriverApiService api;

  setUp(() {
    registerServices();
    api = locator<DriverApiService>() as MockDriverApiService;
  });
  tearDown(() => locator.reset());

  final delivered = DriverOrder(
    id: 'o1',
    status: DriverOrderStatus.delivered,
    total: 14900,
    createdAt: DateTime(2026, 10, 3, 18, 51),
    paymentMethod: 'cash',
    address: 'Santa Fe 3957, Posadas',
    customerName: 'Emilia Villalba',
    lines: const [OrderLine(label: 'Garrafa 10kg', quantity: 1)],
  );

  testGoldens('Bienvenida', (t) async {
    await loadAppFonts();
    await pumpScreen(t, const WelcomeView());
    await check(t, 'welcome');
  });

  testGoldens('Arranque', (t) async {
    await loadAppFonts();
    await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const StartupView()));
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pump();
    await check(t, 'startup');
  });

  testGoldens('Login', (t) async {
    await loadAppFonts();
    await pumpScreen(t, const LoginView());
    await check(t, 'login');
  });

  testGoldens('Recuperar contraseña', (t) async {
    await loadAppFonts();
    await pumpScreen(t, const ForgotPasswordView());
    await check(t, 'forgot_password');
  });

  testGoldens('Menú', (t) async {
    await loadAppFonts();
    await pumpScreen(
        t,
        Scaffold(
          drawer: DriverMenuDrawer(onLogout: () {}),
          body: const SizedBox(),
        ),
        drawer: true);
    await check(t, 'menu');
  });

  testGoldens('Mi perfil', (t) async {
    await loadAppFonts();
    when(api.profile(refresh: true)).thenAnswer((_) async =>
        const DriverProfile(
            userId: 'u',
            fullName: 'Chofer Prueba',
            phone: '+54 9 381 555 0004'));
    when(api.photoUrl()).thenAnswer((_) async => null);
    await pumpScreen(t, const ProfileView());
    await check(t, 'profile');
  });

  testGoldens('Cambiar contraseña', (t) async {
    await loadAppFonts();
    await pumpScreen(t, const ChangePasswordView());
    await check(t, 'change_password');
  });

  testGoldens('Mis entregas vacío', (t) async {
    await loadAppFonts();
    when(api.ordersPage(offset: anyNamed('offset'), limit: anyNamed('limit')))
        .thenAnswer(
            (_) async => const OrdersPage(orders: [], total: 0, offset: 0));
    await pumpScreen(t, const DeliveriesView());
    await check(t, 'deliveries_empty');
  });

  testGoldens('Mis entregas con lista', (t) async {
    await loadAppFonts();
    final orders = [
      delivered,
      DriverOrder(
          id: 'o2',
          status: DriverOrderStatus.delivered,
          total: 9800,
          createdAt: DateTime(2026, 10, 3, 11, 20),
          customerName: 'Marcos Gómez'),
      DriverOrder(
          id: 'o3',
          status: DriverOrderStatus.cancelled,
          total: 4900,
          createdAt: DateTime(2026, 10, 2, 16, 5),
          customerName: 'Lucía Pérez'),
    ];
    when(api.ordersPage(offset: anyNamed('offset'), limit: anyNamed('limit')))
        .thenAnswer(
            (_) async => OrdersPage(orders: orders, total: 3, offset: 0));
    await pumpScreen(t, const DeliveriesView());
    await check(t, 'deliveries_list');
  });

  testGoldens('Detalle de la entrega', (t) async {
    await loadAppFonts();
    await pumpScreen(t, DeliveryDetailView(order: delivered));
    await check(t, 'delivery_detail');
  });

  testGoldens('Mi vehículo', (t) async {
    await loadAppFonts();
    when(api.vehicle()).thenAnswer((_) async => DriverVehicle(
        brand: 'Fiat',
        model: 'Fiorino',
        patent: 'AF123SP',
        type: 'Utilitario',
        assignedAt: DateTime(2026, 9, 1)));
    await pumpScreen(t, const VehicleView());
    await check(t, 'vehicle');
  });

  testGoldens('Tu calificación', (t) async {
    await loadAppFonts();
    when(api.rating())
        .thenAnswer((_) async => const RatingSummary(average: 4.5, count: 12));
    when(api.profile()).thenAnswer((_) async =>
        const DriverProfile(userId: 'u', fullName: 'Chofer Prueba'));
    when(api.photoUrl()).thenAnswer((_) async => null);
    await pumpScreen(t, const RatingView());
    await check(t, 'rating');
  });

  testGoldens('Notificaciones vacío', (t) async {
    await loadAppFonts();
    await pumpScreen(t, const NotificationsView());
    await check(t, 'notifications_empty');
  });

  testGoldens('Notificaciones con lista', (t) async {
    await loadAppFonts();
    final now = DateTime(2026, 10, 10, 12);
    await pumpScreen(
        t,
        NotificationsScreen(now: now, items: [
          DriverNotification(
              title: 'Pedido nuevo',
              content: 'Hay un pedido cerca tuyo',
              createdAt: now),
          DriverNotification(
              title: 'Entrega calificada',
              content: 'Te calificaron con 5 estrellas',
              createdAt: now.subtract(const Duration(days: 1))),
        ]));
    await check(t, 'notifications_list');
  });

  testGoldens('Ayuda', (t) async {
    await loadAppFonts();
    await pumpScreen(t, const HelpView());
    await check(t, 'help');
  });
}
