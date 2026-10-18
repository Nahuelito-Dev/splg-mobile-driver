import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/views/about/about_view.dart';
import 'package:splg_driver/ui/views/deliveries/deliveries_view.dart';
import 'package:splg_driver/ui/views/delivery_detail/delivery_detail_view.dart';
import 'package:splg_driver/ui/views/earnings/earnings_view.dart';
import 'package:splg_driver/ui/views/help/help_view.dart';
import 'package:splg_driver/ui/views/legal/legal_view.dart';
import 'package:splg_driver/ui/views/notifications/notifications_view.dart';
import 'package:splg_driver/ui/views/profile/profile_view.dart';
import 'package:splg_driver/ui/views/rating/rating_view.dart';
import 'package:splg_driver/ui/views/vehicle/vehicle_view.dart';
import 'package:splg_driver/ui/views/welcome/welcome_view.dart';
import 'package:splg_driver/ui/widgets/driver_menu_drawer.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

Widget app(Widget home) => MaterialApp(theme: AppTheme.lightTheme, home: home);

Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  late MockDriverApiService api;
  late MockNavigationService nav;

  setUp(() {
    registerServices();
    api = locator<DriverApiService>() as MockDriverApiService;
    nav = locator<NavigationService>() as MockNavigationService;
  });
  tearDown(() => locator.reset());

  final order = DriverOrder(
    id: 'o1',
    status: DriverOrderStatus.delivered,
    total: 14900,
    createdAt: DateTime(2026, 10, 3, 18, 51),
    paymentMethod: 'cash',
    address: 'Santa Fe 3957',
    customerName: 'Emilia Villalba',
    lines: const [OrderLine(label: 'Garrafa 10kg', quantity: 1)],
  );

  group('Mis entregas', () {
    OrdersPage page(List<DriverOrder> o, {int? total, int offset = 0}) =>
        OrdersPage(orders: o, total: total ?? o.length, offset: offset);

    void stubPage(OrdersPage p) => when(api.ordersPage(
            offset: anyNamed('offset'), limit: anyNamed('limit')))
        .thenAnswer((_) async => p);

    testWidgets('vacío: ilustración, título y mensaje', (t) async {
      stubPage(page([]));
      await t.pumpWidget(app(const DeliveriesView()));
      await settle(t);
      expect(find.text('¡Nada por aquí!'), findsOneWidget);
      expect(find.text('No tenés ninguna entrega realizada.'), findsOneWidget);
    });

    testWidgets('con datos: fecha, monto, estado; tocar abre el detalle',
        (t) async {
      stubPage(page([order]));
      await t.pumpWidget(app(const DeliveriesView()));
      await settle(t);
      expect(find.text('Sábado 3 de octubre'), findsOneWidget);
      expect(find.text('18:51 hs - Emilia Villalba'), findsOneWidget);
      // Las entregas hechas no llevan etiqueta; las demás sí.
      expect(find.text('Entregado'), findsNothing);
      await t.tap(find.text('18:51 hs - Emilia Villalba'));
      verify(nav.navigateToDeliveryDetailView(order: order)).called(1);
    });

    testWidgets('más de una página: al bajar pide la siguiente', (t) async {
      List<DriverOrder> mk(int from, int n) => [
            for (var i = from; i < from + n; i++)
              DriverOrder(
                  id: 'o$i',
                  status: DriverOrderStatus.delivered,
                  total: 100,
                  createdAt:
                      DateTime(2026, 10, 3, 10).subtract(Duration(minutes: i))),
          ];
      when(api.ordersPage(offset: 0, limit: 20))
          .thenAnswer((_) async => page(mk(0, 20), total: 45));
      when(api.ordersPage(offset: 20, limit: 20))
          .thenAnswer((_) async => page(mk(20, 20), total: 45, offset: 20));
      when(api.ordersPage(offset: 40, limit: 20))
          .thenAnswer((_) async => page(mk(40, 5), total: 45, offset: 40));
      await t.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(app(const DeliveriesView()));
      await settle(t);
      for (var i = 0; i < 6; i++) {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -1500));
        await settle(t);
      }
      verify(api.ordersPage(offset: 20, limit: 20)).called(1);
      verify(api.ordersPage(offset: 40, limit: 20)).called(1);
      expect(find.text('45 entregas en total'), findsOneWidget);
    });

    testWidgets('error: muestra el mensaje y Reintentar vuelve a pedir',
        (t) async {
      when(api.ordersPage(offset: anyNamed('offset'), limit: anyNamed('limit')))
          .thenThrow(Exception('boom'));
      await t.pumpWidget(app(const DeliveriesView()));
      await settle(t);
      expect(find.text('Reintentar'), findsOneWidget);
      stubPage(page([]));
      await t.tap(find.text('Reintentar'));
      await settle(t);
      expect(find.text('¡Nada por aquí!'), findsOneWidget);
    });
  });

  testWidgets('Detalle de la entrega muestra monto, cliente y productos',
      (t) async {
    await t.pumpWidget(app(DeliveryDetailView(order: order)));
    expect(find.byKey(const Key('detail-total')), findsOneWidget);
    expect(find.text('\$14.900'), findsOneWidget);
    expect(find.text('Emilia Villalba'), findsOneWidget);
    expect(find.text('1 x Garrafa 10kg'), findsOneWidget);
    expect(find.text('Método de pago: Efectivo'), findsOneWidget);
  });

  group('Mi vehículo', () {
    testWidgets('con vehículo: marca, modelo y patente (sólo lectura)',
        (t) async {
      when(api.vehicle()).thenAnswer((_) async => const DriverVehicle(
          brand: 'Fiat', model: 'Fiorino', patent: 'AF123SP'));
      await t.pumpWidget(app(const VehicleView()));
      await settle(t);
      expect(find.text('Fiat Fiorino'), findsOneWidget);
      expect(find.byKey(const Key('vehicle-patent')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('sin vehículo: estado vacío', (t) async {
      when(api.vehicle()).thenAnswer((_) async => null);
      await t.pumpWidget(app(const VehicleView()));
      await settle(t);
      expect(find.text('¡Nada por aquí!'), findsOneWidget);
    });
  });

  testWidgets('Mi perfil muestra nombre, teléfono y las tres opciones',
      (t) async {
    when(api.profile(refresh: true)).thenAnswer((_) async =>
        const DriverProfile(
            userId: 'u', fullName: 'Chofer Prueba', phone: '+5493815550004'));
    when(api.photoUrl()).thenAnswer((_) async => null);
    await t.pumpWidget(app(const ProfileView()));
    await settle(t);
    expect(find.text('Chofer Prueba'), findsOneWidget);
    expect(find.text('+5493815550004'), findsOneWidget);
    expect(find.text('CP'), findsOneWidget);
    await t.tap(find.text('Mi vehículo'));
    verify(nav.navigateToVehicleView()).called(1);
    await t.tap(find.text('Cambiar contraseña'));
    verify(nav.navigateToChangePasswordView()).called(1);
    await t.tap(find.text('Información personal'));
    verify(nav.navigateToPersonalInfoView()).called(1);
  });

  group('Calificación y estadísticas', () {
    testWidgets('sin calificaciones: estado vacío', (t) async {
      when(api.rating())
          .thenAnswer((_) async => const RatingSummary(average: 0, count: 0));
      await t.pumpWidget(app(const RatingView()));
      await settle(t);
      expect(find.text('¡Nada por aquí!'), findsOneWidget);
    });

    testWidgets('con calificaciones: promedio y cantidad', (t) async {
      when(api.rating()).thenAnswer(
          (_) async => const RatingSummary(average: 4.5, count: 12));
      when(api.profile()).thenAnswer((_) async =>
          const DriverProfile(userId: 'u', fullName: 'Chofer Prueba'));
      when(api.photoUrl()).thenAnswer((_) async => null);
      await t.pumpWidget(app(const RatingView()));
      await settle(t);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('12 calificaciones'), findsOneWidget);
      expect(find.text('Chofer Prueba'), findsOneWidget);
    });

    testWidgets('estadísticas: los chips cambian el período', (t) async {
      final now = DateTime.now();
      when(api.orders()).thenAnswer((_) async => [
            DriverOrder(
                id: 'hoy',
                status: DriverOrderStatus.delivered,
                total: 1000,
                createdAt: now),
            DriverOrder(
                id: 'ayer',
                status: DriverOrderStatus.delivered,
                total: 400,
                createdAt: DateTime(now.year, now.month, now.day)
                    .subtract(const Duration(days: 1, hours: -10))),
          ]);
      await t.pumpWidget(app(const EarningsView()));
      await settle(t);
      for (final chip in ['Mes', 'Semana', 'Ayer', 'Hoy']) {
        expect(find.text(chip), findsOneWidget);
      }
      // Arranca en "Hoy".
      expect(find.text('\$1.000'), findsWidgets);
      await t.tap(find.text('Ayer'));
      await t.pump();
      expect(find.text('\$400'), findsWidgets);
    });

    testWidgets('estadísticas: total del día', (t) async {
      final now = DateTime.now();
      when(api.orders()).thenAnswer((_) async => [
            DriverOrder(
                id: 'a',
                status: DriverOrderStatus.delivered,
                total: 2500,
                createdAt: now),
          ]);
      await t.pumpWidget(app(const EarningsView()));
      await settle(t);
      expect(find.text('\$2.500'), findsWidgets);
      expect(find.text('1 entrega hoy'), findsOneWidget);
    });
  });

  testWidgets('Notificaciones con lista: agrupa en Hoy / Ayer / Anteriores',
      (t) async {
    final now = DateTime(2026, 10, 10, 12);
    await t.pumpWidget(app(NotificationsScreen(now: now, items: [
      DriverNotification(
          title: 'Pedido nuevo', content: 'Cerca tuyo', createdAt: now),
      DriverNotification(
          title: 'Entrega calificada',
          content: '5 estrellas',
          createdAt: now.subtract(const Duration(days: 1))),
      DriverNotification(
          title: 'Aviso',
          content: 'Antiguo',
          createdAt: now.subtract(const Duration(days: 5))),
    ])));
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(find.text('Anteriores'), findsOneWidget);
    expect(find.text('Pedido nuevo'), findsOneWidget);
    expect(find.text('¡Nada por aquí!'), findsNothing);
  });

  testWidgets('Notificaciones: vacío', (t) async {
    await t.pumpWidget(app(const NotificationsView()));
    expect(find.text('¡Nada por aquí!'), findsOneWidget);
    expect(
        find.text('No tenés ninguna notificación pendiente.'), findsOneWidget);
  });

  testWidgets('Ayuda: el buscador filtra las preguntas', (t) async {
    await t.pumpWidget(app(const HelpView()));
    expect(find.text('¿Cómo cambio mi contraseña?'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'contraseña');
    await t.pump();
    expect(find.text('¿Cómo cambio mi contraseña?'), findsOneWidget);
    expect(find.text('¿Cómo recibo los pedidos?'), findsNothing);
    await t.enterText(find.byType(TextField), 'zzzz');
    await t.pump();
    expect(find.text('No encontramos nada con esa búsqueda.'), findsOneWidget);
  });

  testWidgets('Ayuda: acordeón con texto de SPLG', (t) async {
    await t.pumpWidget(app(const HelpView()));
    await t.tap(find.text('¿Cómo me pongo en línea?'));
    await t.pump();
    expect(find.textContaining('Conectarse'), findsOneWidget);
    expect(find.textContaining('Tutu'), findsNothing);
  });

  testWidgets('Acerca de: primera sección abierta', (t) async {
    await t.pumpWidget(app(const AboutView()));
    expect(
        find.textContaining('sistema de pedidos y logística'), findsOneWidget);
  });

  testWidgets('Legal: términos con encabezado y flecha', (t) async {
    await t.pumpWidget(app(const LegalView(document: LegalDocument.terms)));
    await settle(t);
    expect(find.byType(SplgHeader), findsOneWidget);
    expect(find.text('Términos y Condiciones'), findsOneWidget);
  });

  testWidgets(
      'Bienvenida: sin registro, un botón "Comenzar" que lleva al login',
      (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(app(const WelcomeView()));
    await t.pumpAndSettle();
    expect(find.textContaining('Regist'), findsNothing);
    await t.tap(find.text('Comenzar'));
    verify(nav.navigateToLoginView()).called(1);
  });

  group('Menú lateral', () {
    Future<void> openDrawer(WidgetTester t, VoidCallback onLogout) async {
      await t.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          drawer: DriverMenuDrawer(onLogout: onLogout),
          body: const SizedBox(),
        ),
      ));
      await t.pump();
      t.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await t.pumpAndSettle();
    }

    testWidgets('lista todos los ítems pedidos', (t) async {
      await openDrawer(t, () {});
      for (final label in [
        'Mi perfil',
        'Mis entregas',
        'Mi jornada',
        'Mi rendición',
        'Mis comisiones',
        'Cargar combustible',
        'Reportar siniestro',
        'Estadísticas',
        'Tu calificación',
        'Ayuda',
        'Términos y condiciones',
        'Políticas de privacidad',
        'Acerca de SPLG',
        'Cerrar sesión',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    for (final (label, check)
        in <(String, void Function(MockNavigationService))>[
      ('Mi jornada', (n) => verify(n.navigateToWorkdayView()).called(1)),
      ('Mi rendición', (n) => verify(n.navigateToSettlementView()).called(1)),
      (
        'Mis comisiones',
        (n) => verify(n.navigateToCommissionsView()).called(1)
      ),
      (
        'Cargar combustible',
        (n) => verify(n.navigateToFuelLoadView()).called(1)
      ),
      (
        'Reportar siniestro',
        (n) => verify(n.navigateToAccidentView()).called(1)
      ),
      ('Estadísticas', (n) => verify(n.navigateToEarningsView()).called(1)),
      ('Tu calificación', (n) => verify(n.navigateToRatingView()).called(1)),
      ('Ayuda', (n) => verify(n.navigateToHelpView()).called(1)),
      ('Acerca de SPLG', (n) => verify(n.navigateToAboutView()).called(1)),
      (
        'Términos y condiciones',
        (n) => verify(n.navigateToLegalView(document: LegalDocument.terms))
            .called(1)
      ),
      (
        'Políticas de privacidad',
        (n) => verify(n.navigateToLegalView(document: LegalDocument.privacy))
            .called(1)
      ),
    ]) {
      testWidgets('"$label" navega a su pantalla y cierra el menú', (t) async {
        await openDrawer(t, () {});
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        check(nav);
        expect(find.text('Mi perfil'), findsNothing);
      });
    }

    testWidgets('la campana abre las notificaciones', (t) async {
      await openDrawer(t, () {});
      await t.tap(find.byTooltip('Notificaciones'));
      await t.pumpAndSettle();
      verify(nav.navigateToNotificationsView()).called(1);
    });

    testWidgets(
        'Cerrar sesión pide confirmación y recién ahí llama al callback',
        (t) async {
      var logouts = 0;
      await openDrawer(t, () => logouts++);
      await t.tap(find.text('Cerrar sesión'));
      await t.pumpAndSettle();
      expect(logouts, 0);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(logouts, 0);
      await t.tap(find.text('Cerrar sesión'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(SplgButton, 'Cerrar sesión').last);
      await t.pumpAndSettle();
      expect(logouts, 1);
      expect(find.text('Mi perfil'), findsNothing);
    });

    testWidgets('Mi perfil y Mis entregas navegan', (t) async {
      await openDrawer(t, () {});
      await t.tap(find.text('Mi perfil'));
      await t.pumpAndSettle();
      verify(nav.navigateToProfileView()).called(1);
      await openDrawer(t, () {});
      await t.tap(find.text('Mis entregas'));
      await t.pumpAndSettle();
      verify(nav.navigateToDeliveriesView()).called(1);
    });
  });
}
