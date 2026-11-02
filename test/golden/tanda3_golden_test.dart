import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog.dart';
import 'package:splg_driver/ui/views/completed/completed_view.dart';
import 'package:splg_driver/ui/views/completed/completed_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery/delivery_view.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery_qr/delivery_qr_view.dart';
import 'package:splg_driver/ui/views/delivery_qr/delivery_qr_viewmodel.dart';
import 'package:splg_driver/ui/views/payment/payment_view.dart';
import 'package:splg_driver/ui/views/payment/payment_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';

/// Pantallas del flujo del pedido (393x852, 1x). El mapa va como placeholder.
Future<void> pump(WidgetTester t, Widget home) async {
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
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> leave(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
}

Future<void> check(WidgetTester t, String name) => expectLater(
    find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

void main() {
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDriverSocketService socket;
  late List<DialogResponse> responses;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    responses = [];
    when(trips.order('o1')).thenAnswer((_) async => trip());
    when(trips.customerRating('c1'))
        .thenAnswer((_) async => const RatingSummary(average: 4.5, count: 12));
    when(trips.deliveryCode('o1'))
        .thenAnswer((_) async => const DeliveryCodeInfo('A1B2C3D4E5'));
    DeliveryView.debugMapBuilder = (_, __) => Container(
        color: const Color(0xFFE8E6E1),
        child: const Center(child: Text('mapa')));
    DeliveryView.debugViewModelFactory = (id) => DeliveryViewModel(
        orderId: id, trips: trips, pollInterval: const Duration(hours: 1));
    DeliveryQrView.debugViewModelFactory = (id) => DeliveryQrViewModel(
        orderId: id, trips: trips, pollInterval: const Duration(hours: 1));
    PaymentView.debugViewModelFactory =
        (id) => PaymentViewModel(orderId: id, trips: trips);
    CompletedView.debugViewModelFactory =
        (id) => CompletedViewModel(orderId: id, trips: trips, goHome: () {});
  });
  tearDown(() {
    DeliveryView.debugMapBuilder = null;
    DeliveryView.debugViewModelFactory = null;
    DeliveryQrView.debugViewModelFactory = null;
    PaymentView.debugViewModelFactory = null;
    CompletedView.debugViewModelFactory = null;
    NavigationLauncher.launcher = null;
    locator.reset();
  });

  OrderOfferDialog offer() => OrderOfferDialog(
        request: DialogRequest(data: {
          'orderId': 'o1',
          'totalAmount': 28310,
          'paymentMethod': 'cash',
          'expiresAt':
              DateTime.now().add(const Duration(seconds: 25)).toIso8601String(),
        }),
        completer: responses.add,
      );

  group('Oferta de pedido', () {
    testGoldens('muestra monto, cliente, dirección, garrafas, pago y cuenta',
        (t) async {
      await loadAppFonts();
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'pending'));
      await pump(t, offer());
      expect(find.byKey(const Key('offer-total')), findsOneWidget);
      expect(find.text(r'$28.310'), findsOneWidget);
      expect(find.text('Cliente Prueba'), findsOneWidget);
      expect(find.text('4.5 (12)'), findsOneWidget);
      expect(find.text('Buenos Aires 4114, Centro, Posadas, Misiones'),
          findsOneWidget);
      expect(find.text('2 x Garrafa 10kg'), findsOneWidget);
      expect(find.text('Franja 08:00 a 12:00'), findsOneWidget);
      expect(find.textContaining('La oferta vence en'), findsOneWidget);
      expect(tester(t).takeException(), isNull);
      await check(t, 'offer');
      await leave(t);
    });

    testWidgets('Aceptar pregunta el mapa y devuelve la elección', (t) async {
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'pending'));
      await pump(t, offer());
      await t.tap(find.text('Aceptar pedido'));
      await t.pumpAndSettle();
      expect(find.text('Permanecer en SPLG'), findsOneWidget);
      expect(find.text('Ir a Google Maps'), findsOneWidget);
      expect(find.text('Ir a Waze'), findsOneWidget);
      await t.tap(find.text('Ir a Waze'));
      await t.pumpAndSettle();
      expect(responses.single.confirmed, true);
      expect((responses.single.data as Map)['map'], 'waze');
      expect((responses.single.data as Map)['lat'], closeTo(-27.357482, 1e-6));
      await leave(t);
    });

    testWidgets('Volver rechaza', (t) async {
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'pending'));
      await pump(t, offer());
      await t.tap(find.text('Volver'));
      await t.pump();
      expect(responses.single.confirmed, false);
      await leave(t);
    });

    testWidgets('si no se puede leer el pedido lo dice y deja decidir',
        (t) async {
      when(trips.order('o1')).thenThrow(Exception('x'));
      await pump(t, offer());
      expect(find.byKey(const Key('offer-load-error')), findsOneWidget);
      await t.tap(find.text('Aceptar pedido'));
      await t.pump();
      expect(responses.single.confirmed, true);
      await leave(t);
    });

    testWidgets('en pantalla chica no desborda', (t) async {
      when(trips.order('o1')).thenAnswer((_) async => trip(status: 'pending'));
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t
          .pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: offer()));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      await leave(t);
    });
  });

  group('Pedido en curso', () {
    testGoldens('aceptado: "Salir hacia el cliente"', (t) async {
      await loadAppFonts();
      await pump(t, const DeliveryView(orderId: 'o1'));
      expect(find.text('Pedido aceptado'), findsOneWidget);
      expect(find.text('Salir hacia el cliente'), findsWidgets);
      expect(find.text('Llegué / Entregar'), findsNothing);
      expect(find.text('Llamar'), findsOneWidget);
      expect(find.text('Navegar'), findsOneWidget);
      await check(t, 'delivery_accepted');
      await leave(t);
    });

    testGoldens('en camino: "Llegué / Entregar"', (t) async {
      await loadAppFonts();
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'out_for_delivery'));
      await pump(t, const DeliveryView(orderId: 'o1'));
      expect(find.text('En camino'), findsOneWidget);
      expect(find.text('Llegué / Entregar'), findsOneWidget);
      expect(find.byKey(const Key('trip-leave')), findsNothing);
      await check(t, 'delivery_on_the_way');
      await leave(t);
    });

    testWidgets('con el pedido en curso el menú está a mano y abre', (t) async {
      await pump(t, const DeliveryView(orderId: 'o1'));
      expect(find.byKey(const Key('trip-menu')), findsOneWidget);
      await t.tap(find.byKey(const Key('trip-menu')));
      await t.pumpAndSettle();
      expect(find.text('Mi jornada'), findsOneWidget);
      expect(find.text('Mi rendición'), findsOneWidget);
      expect(find.text('Cargar combustible'), findsOneWidget);
      expect(find.text('Reportar siniestro'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsNothing);
      await leave(t);
    });

    testWidgets('tocar "Salir" manda on_the_way', (t) async {
      await pump(t, const DeliveryView(orderId: 'o1'));
      await t.tap(find.byKey(const Key('trip-leave')));
      await t.pump();
      verify(trips.setStatus('o1', 'on_the_way')).called(1);
      await leave(t);
    });

    testWidgets('Navegar abre el pop-up de mapas y Waze cae a la web',
        (t) async {
      final opened = <Uri>[];
      NavigationLauncher.launcher = (u) async {
        opened.add(u);
        return u.scheme == 'https';
      };
      await pump(t, const DeliveryView(orderId: 'o1'));
      await t.tap(find.byKey(const Key('trip-navigate')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ir a Waze'));
      await t.pumpAndSettle();
      expect(opened.map((u) => u.scheme), ['waze', 'https']);
      expect(find.text('No tenés Waze instalado: abrimos la versión web.'),
          findsOneWidget);
      await leave(t);
    });

    testWidgets('sin red al cargar: error con "Reintentar"', (t) async {
      when(trips.order('o1')).thenThrow(Exception('x'));
      await pump(t, const DeliveryView(orderId: 'o1'));
      expect(find.byKey(const Key('delivery-load-error')), findsOneWidget);
      when(trips.order('o1')).thenAnswer((_) async => trip());
      await t.tap(find.text('Reintentar'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Pedido aceptado'), findsOneWidget);
      await leave(t);
    });
  });

  group('Finalización (QR)', () {
    testGoldens('muestra el QR grande con las instrucciones', (t) async {
      await loadAppFonts();
      await pump(t, const DeliveryQrView(orderId: 'o1'));
      expect(find.byKey(const Key('qr-code')), findsOneWidget);
      expect(find.text('A1B2C3D4E5'), findsOneWidget);
      expect(find.byKey(const Key('qr-waiting')), findsOneWidget);
      verify(trips.deliveryCode('o1')).called(1);
      await check(t, 'qr');
      await leave(t);
    });

    testWidgets('«Generar código nuevo» pide confirmación y cambia el código',
        (t) async {
      when(trips.regenerateDeliveryCode('o1'))
          .thenAnswer((_) async => '482913');
      await pump(t, const DeliveryQrView(orderId: 'o1'));
      await t.ensureVisible(find.byKey(const Key('qr-regenerate')));
      await t.tap(find.byKey(const Key('qr-regenerate')));
      await t.pump();
      expect(find.byKey(const Key('qr-regenerate-ask')), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('qr-regenerate-confirm')));
      await t.tap(find.byKey(const Key('qr-regenerate-confirm')));
      await t.pump();
      await t.pump();
      expect(find.text('482 913'), findsOneWidget);
      expect(find.text('A1B2C3D4E5'), findsNothing);
      verify(trips.regenerateDeliveryCode('o1')).called(1);
      await leave(t);
    });

    testWidgets('bloqueado: aviso claro y botón que genera el código nuevo',
        (t) async {
      when(trips.deliveryCode('o1')).thenAnswer((_) async =>
          const DeliveryCodeInfo('A1B2C3D4E5', attempts: 5, blocked: true));
      when(trips.regenerateDeliveryCode('o1'))
          .thenAnswer((_) async => '482913');
      await pump(t, const DeliveryQrView(orderId: 'o1'));
      expect(find.byKey(const Key('qr-blocked')), findsOneWidget);
      expect(
          find.textContaining('El cliente se equivocó 5 veces: generá un '
              'código nuevo y dictáselo'),
          findsOneWidget);
      expect(find.byKey(const Key('qr-waiting')), findsNothing);
      expect(find.byKey(const Key('qr-code')), findsNothing);
      expect(find.byKey(const Key('qr-code-text')), findsNothing);
      expect(find.text('A1B2C3D4E5'), findsNothing);
      expect(find.textContaining('dictale este código'), findsNothing);
      expect(find.byKey(const Key('qr-regenerate')), findsOneWidget);

      await t.ensureVisible(find.byKey(const Key('qr-regenerate')));
      await t.tap(find.byKey(const Key('qr-regenerate')));
      await t.pump();
      await t.pump();

      verify(trips.regenerateDeliveryCode('o1')).called(1);
      expect(find.byKey(const Key('qr-blocked')), findsNothing);
      expect(find.text('482 913'), findsOneWidget);
      expect(find.byKey(const Key('qr-waiting')), findsOneWidget);
      await leave(t);
    });

    testWidgets('desde el 3.er error avisa cuántas veces, sin bloquear',
        (t) async {
      when(trips.deliveryCode('o1')).thenAnswer(
          (_) async => const DeliveryCodeInfo('A1B2C3D4E5', attempts: 3));
      await pump(t, const DeliveryQrView(orderId: 'o1'));
      expect(find.byKey(const Key('qr-attempts-warning')), findsOneWidget);
      expect(find.text('El cliente se equivocó 3 veces'), findsOneWidget);
      expect(find.byKey(const Key('qr-blocked')), findsNothing);
      expect(find.byKey(const Key('qr-waiting')), findsOneWidget);
      await leave(t);
    });

    testWidgets('si generar el código falla (sin bloqueo), se ve el motivo',
        (t) async {
      when(trips.regenerateDeliveryCode('o1'))
          .thenThrow(StateError('El pedido ya no está en camino'));
      await pump(t, const DeliveryQrView(orderId: 'o1'));
      await t.ensureVisible(find.byKey(const Key('qr-regenerate')));
      await t.tap(find.byKey(const Key('qr-regenerate')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('qr-regenerate-confirm')));
      await t.tap(find.byKey(const Key('qr-regenerate-confirm')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('qr-regenerate-error')), findsOneWidget);
      expect(find.text('El pedido ya no está en camino'), findsOneWidget);
      await leave(t);
    });

    testWidgets('sin código: error y reintento', (t) async {
      when(trips.deliveryCode('o1')).thenThrow(StateError('Sin código'));
      await pump(t, const DeliveryQrView(orderId: 'o1'));
      expect(find.byKey(const Key('qr-error')), findsOneWidget);
      expect(find.byKey(const Key('qr-code')), findsNothing);
      await leave(t);
    });

    testWidgets('la flecha vuelve al pedido', (t) async {
      await pump(t, const DeliveryQrView(orderId: 'o1'));
      await t.tap(find.byTooltip('Volver'));
      verify(nav.back()).called(1);
      await leave(t);
    });
  });

  group('Cobro', () {
    testGoldens('efectivo', (t) async {
      await loadAppFonts();
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      await pump(t, const PaymentView(orderId: 'o1'));
      expect(find.text('Método de pago: Efectivo'), findsOneWidget);
      expect(find.text('Total a cobrar'), findsOneWidget);
      expect(find.text(r'$28.310'), findsOneWidget);
      expect(find.text('Pago recibido'), findsOneWidget);
      await check(t, 'payment_cash');
      await leave(t);
    });

    testGoldens('Mercado Pago pendiente', (t) async {
      await loadAppFonts();
      when(trips.order('o1')).thenAnswer((_) async => trip(
          status: 'delivered', method: 'online', paymentStatus: 'pending'));
      await pump(t, const PaymentView(orderId: 'o1'));
      expect(find.text('Método de pago: Mercado Pago'), findsOneWidget);
      expect(find.byKey(const Key('payment-online-status')), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Pago recibido'), findsNothing);
      await check(t, 'payment_online');
      await leave(t);
    });
  });

  group('Pedido completado y calificación', () {
    testGoldens('pedido completado', (t) async {
      await loadAppFonts();
      await pump(t, const CompletedView(orderId: 'o1'));
      expect(find.text('¡Pedido completado!'), findsOneWidget);
      await check(t, 'completed');
      await leave(t);
    });

    testGoldens('hoja "Calificá a tu cliente"', (t) async {
      await loadAppFonts();
      await pump(t, const CompletedView(orderId: 'o1'));
      await t.tap(find.byKey(const Key('completed-rate')));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('4 estrellas'));
      await t.pump();
      await check(t, 'rating_sheet');
      await leave(t);
    });

    testWidgets('calificar envía y muestra el agradecimiento', (t) async {
      await pump(t, const CompletedView(orderId: 'o1'));
      await t.tap(find.byKey(const Key('completed-rate')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rating-submit')));
      await t.pump();
      expect(find.byKey(const Key('rating-error')), findsOneWidget);
      verifyNever(trips.rateCustomer(any, any, any));
      await t.tap(find.byTooltip('5 estrellas'));
      await t.pump();
      await t.tap(find.byKey(const Key('rating-submit')));
      await t.pumpAndSettle();
      verify(trips.rateCustomer('o1', 5, '')).called(1);
      expect(find.byKey(const Key('completed-thanks')), findsOneWidget);
      await leave(t);
    });
  });

  testWidgets('sin referencia a "Tutu" en los textos del flujo', (t) async {
    await pump(t, const DeliveryView(orderId: 'o1'));
    expect(find.textContaining('Tutu'), findsNothing);
    await leave(t);
    expect(socket, isNotNull);
  });
}

WidgetTester tester(WidgetTester t) => t;
