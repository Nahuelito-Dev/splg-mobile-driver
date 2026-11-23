import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog.dart';
import 'package:splg_driver/ui/views/completed/completed_view.dart';
import 'package:splg_driver/ui/views/completed/completed_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery/delivery_view.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery_code/delivery_code_view.dart';
import 'package:splg_driver/ui/views/delivery_code/delivery_code_viewmodel.dart';
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
    DeliveryView.debugMapBuilder = (_, __) => Container(
        color: const Color(0xFFE8E6E1),
        child: const Center(child: Text('mapa')));
    DeliveryView.debugViewModelFactory = (id) => DeliveryViewModel(
        orderId: id, trips: trips, pollInterval: const Duration(hours: 1));
    DeliveryCodeView.debugViewModelFactory = (id) => DeliveryCodeViewModel(
        orderId: id, trips: trips, pollInterval: const Duration(hours: 1));
    PaymentView.debugViewModelFactory =
        (id) => PaymentViewModel(orderId: id, trips: trips);
    CompletedView.debugViewModelFactory =
        (id) => CompletedViewModel(orderId: id, trips: trips, goHome: () {});
  });
  tearDown(() {
    DeliveryView.debugMapBuilder = null;
    DeliveryView.debugViewModelFactory = null;
    DeliveryCodeView.debugViewModelFactory = null;
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

    testWidgets(
        'plegado: esconde cliente y botones, pero la acción y el error se ven',
        (t) async {
      when(trips.setStatus('o1', 'on_the_way')).thenThrow(Exception('x'));
      await pump(t, const DeliveryView(orderId: 'o1'));
      await t.tap(find.byKey(const Key('trip-collapse')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trip-call')), findsNothing);
      expect(find.byKey(const Key('trip-navigate')), findsNothing);
      expect(find.byKey(const Key('trip-leave')), findsOneWidget);

      await t.tap(find.byKey(const Key('trip-leave')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trip-message')), findsOneWidget);

      await t.tap(find.byKey(const Key('trip-collapse')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trip-call')), findsOneWidget);
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

  group('Finalización (código del cliente)', () {
    Future<void> tipear(WidgetTester t, String digits) async {
      for (final d in digits.split('')) {
        await t.ensureVisible(find.byKey(Key('code-key-$d')));
        await t.tap(find.byKey(Key('code-key-$d')));
        await t.pump();
      }
    }

    testGoldens('pide el código con teclado numérico y botón deshabilitado',
        (t) async {
      await loadAppFonts();
      await pump(t, const DeliveryCodeView(orderId: 'o1'));
      expect(find.text('Pedile el código al cliente'), findsOneWidget);
      expect(find.byKey(const Key('code-keypad')), findsOneWidget);
      expect(find.byKey(const Key('qr-code')), findsNothing);
      final boton = t.widget<SplgButton>(find.byKey(const Key('code-submit')));
      expect(boton.onPressed, isNull);
      await tipear(t, '4829');
      await check(t, 'codigo-entrega');
      await leave(t);
    });

    testWidgets('con 6 dígitos habilita «Confirmar entrega» y la manda',
        (t) async {
      when(trips.confirmDelivery('o1',
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenAnswer((_) async {});
      final loc = locator<LocationService>() as MockLocationService;
      when(loc.locationBlock()).thenAnswer((_) async => null);
      when(loc.currentPosition).thenReturn(fix());
      when(nav.currentRoute).thenReturn(Routes.paymentView);
      await pump(t, const DeliveryCodeView(orderId: 'o1'));
      await tipear(t, '482913');
      final boton = t.widget<SplgButton>(find.byKey(const Key('code-submit')));
      expect(boton.onPressed, isNotNull);
      await t.ensureVisible(find.byKey(const Key('code-submit')));
      await t.tap(find.byKey(const Key('code-submit')));
      await t.pump();
      await t.pump();
      verify(trips.confirmDelivery('o1',
              code: '482913',
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .called(1);
      verify(nav.replaceWithPaymentView(orderId: 'o1')).called(1);
      await leave(t);
    });

    testWidgets('«Borrar» saca el último dígito', (t) async {
      await pump(t, const DeliveryCodeView(orderId: 'o1'));
      await tipear(t, '12');
      await t.tap(find.byKey(const Key('code-key-delete')));
      await t.pump();
      expect(
          find.descendant(
              of: find.byKey(const Key('code-box-0')),
              matching: find.text('1')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('code-box-1')),
              matching: find.text('2')),
          findsNothing);
      await leave(t);
    });

    testWidgets('código incorrecto: se ve el error en castellano', (t) async {
      when(trips.confirmDelivery('o1',
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                  requestOptions: RequestOptions(path: ''),
                  statusCode: 400,
                  data: {'code': 'DELIVERY_CODE_INCORRECTO'})));
      final loc = locator<LocationService>() as MockLocationService;
      when(loc.locationBlock()).thenAnswer((_) async => null);
      when(loc.currentPosition).thenReturn(fix());
      await pump(t, const DeliveryCodeView(orderId: 'o1'));
      await tipear(t, '482913');
      await t.ensureVisible(find.byKey(const Key('code-submit')));
      await t.tap(find.byKey(const Key('code-submit')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('code-error')), findsOneWidget);
      expect(find.text('El código no es correcto.'), findsOneWidget);
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      await leave(t);
    });

    testWidgets('bloqueado: aviso claro y sin teclado útil', (t) async {
      when(trips.confirmDelivery('o1',
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                  requestOptions: RequestOptions(path: ''),
                  statusCode: 409,
                  data: {'code': 'DELIVERY_CODE_BLOQUEADO'})));
      final loc = locator<LocationService>() as MockLocationService;
      when(loc.locationBlock()).thenAnswer((_) async => null);
      when(loc.currentPosition).thenReturn(fix());
      await pump(t, const DeliveryCodeView(orderId: 'o1'));
      await tipear(t, '482913');
      await t.ensureVisible(find.byKey(const Key('code-submit')));
      await t.tap(find.byKey(const Key('code-submit')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('code-blocked')), findsOneWidget);
      expect(
          find.textContaining('Pedile al cliente que genere un código nuevo'),
          findsOneWidget);
      final boton = t.widget<SplgButton>(find.byKey(const Key('code-submit')));
      expect(boton.onPressed, isNull);
      await leave(t);
    });

    testWidgets('si el pedido no carga: error y reintento', (t) async {
      when(trips.order('o1')).thenThrow(StateError('x'));
      await pump(t, const DeliveryCodeView(orderId: 'o1'));
      expect(find.byKey(const Key('code-load-error')), findsOneWidget);
      expect(find.byKey(const Key('code-keypad')), findsNothing);
      await leave(t);
    });

    testWidgets('la flecha vuelve al pedido', (t) async {
      await pump(t, const DeliveryCodeView(orderId: 'o1'));
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
