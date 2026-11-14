import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/payment_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
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
import 'support.dart';

/// NavigationService real que anota los reemplazos de ruta (y puede fallar a
/// pedido, para probar qué pasa si el cobro no se abre).
class _NavEspia extends NavigationService {
  final reemplazos = <String>[];
  bool fallarCobro = false;

  /// El cobro devuelve null sin navegar (sin navegador, duplicado bloqueado).
  bool cobroNulo = false;

  @override
  Future<T?>? replaceWith<T>(
    String routeName, {
    dynamic arguments,
    int? id,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    RouteTransitionsBuilder? transition,
  }) {
    reemplazos.add(routeName);
    if (fallarCobro && routeName == Routes.paymentView) {
      throw StateError('sin navegador');
    }
    if (cobroNulo && routeName == Routes.paymentView) return null;
    return super.replaceWith<T>(routeName,
        arguments: arguments,
        id: id,
        preventDuplicates: preventDuplicates,
        parameters: parameters,
        transition: transition);
  }
}

/// TripService con el estado del flujo de verdad (el resto, mock).
class _Trips extends MockTripService {
  String? _activo;
  String? _cobro;
  @override
  String? get activeOrderId => _activo;
  @override
  set activeOrderId(String? v) => _activo = v;
  @override
  String? get paymentOpenedFor => _cobro;
  @override
  set paymentOpenedFor(String? v) => _cobro = v;
  @override
  void beginFlow(String? orderId) {
    if (activeOrderId != orderId) paymentOpenedFor = null;
    activeOrderId = orderId;
  }

  @override
  void endFlow() {
    activeOrderId = null;
    paymentOpenedFor = null;
  }
}

/// Final de la entrega con la navegación real: Inicio → pedido → QR. Lo que
/// cierra el QR (cancelado, entrega confirmada) no se repite al volver a la
/// pantalla del pedido.
void main() {
  late _Trips trips;
  late _NavEspia nav;
  late MockDialogService dialogs;
  late StreamController<Map<String, dynamic>> cancelado;
  late String estado;
  DeliveryViewModel? pedido;
  late int cobros;
  late Duration sondeoPedido;

  setUp(() {
    registerServices();
    trips = _Trips();
    locator.unregister<TripService>();
    locator.registerSingleton<TripService>(trips);
    locator.unregister<NavigationService>();
    nav = _NavEspia();
    locator.registerSingleton<NavigationService>(nav);
    dialogs = locator<DialogService>() as MockDialogService;
    final socket = locator<DriverSocketService>() as MockDriverSocketService;
    cancelado = StreamController<Map<String, dynamic>>.broadcast();
    when(socket.orderCancelled).thenAnswer((_) => cancelado.stream);
    when(socket.deliveryCodeFailed).thenAnswer((_) => const Stream.empty());
    when(socket.orderAddressChanged).thenAnswer((_) => const Stream.empty());
    final loc = locator<LocationService>() as MockLocationService;
    when(loc.currentPosition).thenReturn(null);
    when(loc.positionStream).thenAnswer((_) => const Stream.empty());
    estado = 'out_for_delivery';
    when(trips.order('o1')).thenAnswer((_) async => trip(status: estado));
    when(trips.customerRating(any)).thenAnswer((_) async => null);
    when(trips.deliveryCode('o1'))
        .thenAnswer((_) async => const DeliveryCodeInfo('482913'));
    final pagos = locator<PaymentRepository>() as MockPaymentRepository;
    cobros = 0;
    pedido = null;
    sondeoPedido = const Duration(hours: 1);
    DeliveryView.debugMapBuilder = (_, __) => const SizedBox();
    DeliveryView.debugViewModelFactory = (id) => pedido = DeliveryViewModel(
        orderId: id, trips: trips, pollInterval: sondeoPedido);
    DeliveryQrView.debugViewModelFactory = (id) => DeliveryQrViewModel(
        orderId: id,
        trips: trips,
        pollInterval: const Duration(milliseconds: 100));
    PaymentView.debugViewModelFactory = (id) {
      cobros++;
      return PaymentViewModel(orderId: id, trips: trips, payments: pagos);
    };
  });

  tearDown(() async {
    DeliveryView.debugMapBuilder = null;
    DeliveryView.debugViewModelFactory = null;
    DeliveryQrView.debugViewModelFactory = null;
    PaymentView.debugViewModelFactory = null;
    await cancelado.close();
    locator.reset();
  });

  Future<void> avanzar(WidgetTester t, [int veces = 6]) async {
    for (var i = 0; i < veces; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  /// Inicio → pedido en camino → QR abierto.
  Future<void> hastaElQr(WidgetTester t) async {
    await loadAppFonts();
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      navigatorKey: StackedService.navigatorKey,
      navigatorObservers: [StackedService.routeObserver],
      onGenerateRoute: StackedRouter().onGenerateRoute,
      home: const Scaffold(body: Text('Inicio')),
    ));
    trips.beginFlow('o1');
    unawaited(nav.navigateToDeliveryView(orderId: 'o1'));
    await avanzar(t);
    expect(pedido, isNotNull);
    unawaited(pedido!.openDeliveryQr());
    await avanzar(t);
    expect(find.byKey(const Key('qr-code')), findsOneWidget);
  }

  Future<void> salir(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await avanzar(t, 2);
  }

  testWidgets('el admin cancela con el QR abierto: un solo aviso', (t) async {
    await hastaElQr(t);
    estado = 'cancelled';
    cancelado.add({'orderId': 'o1'});
    await avanzar(t);
    verify(dialogs.showDialog(
            title: 'Pedido cancelado', description: anyNamed('description')))
        .called(1);
    expect(find.text('Inicio'), findsOneWidget);
    expect(trips.activeOrderId, isNull);
    await salir(t);
  });

  testWidgets('el cliente confirma con el QR abierto: el cobro se abre una vez',
      (t) async {
    await hastaElQr(t);
    estado = 'delivered';
    await avanzar(t, 10);
    expect(nav.reemplazos.where((r) => r == Routes.paymentView).length, 1);
    expect(cobros, 1);
    expect(find.byType(PaymentView), findsOneWidget);
    expect(trips.paymentOpenedFor, 'o1');
    await salir(t);
  });

  testWidgets('si el cobro no se abre, no queda marcado y el QR sigue',
      (t) async {
    await hastaElQr(t);
    nav.fallarCobro = true;
    estado = 'delivered';
    await avanzar(t, 2);
    expect(nav.reemplazos, contains(Routes.paymentView));
    expect(trips.paymentOpenedFor, isNull);
    expect(find.byKey(const Key('qr-code')), findsOneWidget);
    // Con la navegación de vuelta, el próximo sondeo abre el cobro.
    nav.fallarCobro = false;
    await avanzar(t, 6);
    expect(find.byType(PaymentView), findsOneWidget);
    expect(trips.paymentOpenedFor, 'o1');
    await salir(t);
  });

  testWidgets(
      'el cobro no se abre sin error (replaceWith null): no queda marcado y '
      'el QR reintenta', (t) async {
    await hastaElQr(t);
    nav.cobroNulo = true;
    estado = 'delivered';
    await avanzar(t, 2);
    expect(nav.reemplazos, contains(Routes.paymentView));
    expect(find.byType(PaymentView), findsNothing);
    expect(trips.paymentOpenedFor, isNull);
    expect(find.byKey(const Key('qr-code')), findsOneWidget);
    nav.cobroNulo = false;
    await avanzar(t, 6);
    expect(find.byType(PaymentView), findsOneWidget);
    expect(trips.paymentOpenedFor, 'o1');
    await salir(t);
  });

  testWidgets(
      'desde la pantalla del pedido, replaceWith null: no queda marcado y '
      'reintenta abrir el cobro', (t) async {
    sondeoPedido = const Duration(milliseconds: 300);
    await hastaElQr(t);
    nav.cobroNulo = true;
    estado = 'delivered';
    // Vuelve con «atrás» justo cuando el cliente confirmó: el cobro lo abre
    // la pantalla del pedido.
    await t.tap(find.byTooltip('Volver'));
    await avanzar(t, 4);
    expect(nav.reemplazos, contains(Routes.paymentView));
    expect(find.byType(PaymentView), findsNothing);
    expect(find.byType(DeliveryView), findsOneWidget);
    expect(trips.paymentOpenedFor, isNull);
    nav.cobroNulo = false;
    await avanzar(t, 6);
    expect(find.byType(PaymentView), findsOneWidget);
    expect(trips.paymentOpenedFor, 'o1');
    await salir(t);
  });

  testWidgets('vuelve del QR con «atrás» y el pedido sigue: retoma', (t) async {
    await hastaElQr(t);
    await t.tap(find.byTooltip('Volver'));
    await avanzar(t);
    expect(find.byKey(const Key('qr-code')), findsNothing);
    expect(find.byType(DeliveryView), findsOneWidget);
    verifyNever(dialogs.showDialog(
        title: anyNamed('title'), description: anyNamed('description')));
    await salir(t);
  });

  testWidgets(
      'vuelve con «atrás» y el pedido ya estaba cancelado: avisa una vez',
      (t) async {
    await hastaElQr(t);
    estado = 'cancelled';
    // Toca «atrás» antes de que el sondeo del QR lo vea.
    await t.tap(find.byTooltip('Volver'));
    await avanzar(t);
    verify(dialogs.showDialog(
            title: 'Pedido cancelado', description: anyNamed('description')))
        .called(1);
    await salir(t);
  });
}
