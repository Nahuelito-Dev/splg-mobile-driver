import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/truck_load.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/payment_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_driver/ui/views/my_load/my_load_view.dart';
import 'package:splg_driver/ui/views/my_load/my_load_viewmodel.dart';
import 'package:splg_driver/ui/views/payment/payment_viewmodel.dart';
import 'package:splg_driver/ui/widgets/driver_menu_drawer.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';
import 'support.dart';

Widget app(Widget home) => MaterialApp(theme: AppTheme.lightTheme, home: home);

DioException offline() =>
    DioException(requestOptions: RequestOptions(path: ''));

class _HomeConAviso extends HomeViewModel {
  _HomeConAviso(String? motivo) {
    hasLocationPermission = true;
    noOrdersReason = motivo;
  }

  @override
  Future<void> initialize() async {}
}

void main() {
  late MockDriverApiService api;
  late MockNavigationService nav;
  late MockTripService trips;
  late MockPaymentRepository payments;

  setUp(() {
    registerServices();
    api = locator<DriverApiService>() as MockDriverApiService;
    nav = locator<NavigationService>() as MockNavigationService;
    trips = locator<TripService>() as MockTripService;
    payments = locator<PaymentRepository>() as MockPaymentRepository;
  });
  tearDown(() => locator.reset());

  group('Modelo de GET /truck-loads/mine', () {
    test('lee la carga con la forma del DTO', () {
      final m = myLoad();
      expect(m.requireOpenTruckLoad, true);
      final l = m.load!;
      expect(l.number, 12);
      expect(l.status, TruckLoadStatus.onRoute);
      expect(l.carPatent, 'AB123CD');
      expect(l.originName, 'Depósito central');
      final i = l.items.single;
      expect(i.type, 'Garrafa 25kg');
      expect(i.loadedEmpty, 10);
      expect(i.expectedFull, 10);
      expect(i.collectedEmpty, 28);
    });

    test('load null: sin carga', () {
      expect(myLoad(open: false).load, isNull);
    });
  });

  group('Mi carga', () {
    testWidgets('con carga: camión, depósito, estado e ítems', (t) async {
      when(api.myTruckLoad()).thenAnswer((_) async => myLoad());
      await t.pumpWidget(app(const MyLoadView()));
      await t.pumpAndSettle();
      expect(find.text('Carga N° 12'), findsOneWidget);
      expect(find.text('En ruta'), findsOneWidget);
      expect(find.text('AB123CD'), findsOneWidget);
      expect(find.text('Depósito central'), findsOneWidget);
      // El tipo ya trae la palabra "Garrafa": se muestra tal cual.
      expect(find.text('Garrafa 25kg'), findsOneWidget);
      expect(find.textContaining('Garrafa Garrafa'), findsNothing);
      expect(find.text('Llenas cargadas'), findsOneWidget);
      expect(find.text('Vacías con las que salió'), findsOneWidget);
      expect(find.text('Entregadas'), findsOneWidget);
      expect(find.text('Vacías recolectadas'), findsOneWidget);
      expect(
          t
              .widget<Text>(
                  find.byKey(const Key('my-load-left-full-Garrafa 25kg')))
              .data,
          '10');
    });

    testWidgets('sin carga: estado vacío claro', (t) async {
      when(api.myTruckLoad())
          .thenAnswer((_) async => myLoad(open: false, require: true));
      await t.pumpWidget(app(const MyLoadView()));
      await t.pumpAndSettle();
      expect(find.text('Sin carga abierta'), findsOneWidget);
      expect(find.textContaining('te pide una carga abierta'), findsOneWidget);
      expect(find.text('Carga N° 12'), findsNothing);
    });

    testWidgets('pull-to-refresh relee y muestra la carga nueva', (t) async {
      var open = false;
      when(api.myTruckLoad())
          .thenAnswer((_) async => myLoad(open: open, require: true));
      await t.pumpWidget(app(const MyLoadView()));
      await t.pumpAndSettle();
      expect(find.text('Sin carga abierta'), findsOneWidget);
      open = true;
      await t.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await t.pumpAndSettle();
      expect(find.text('Carga N° 12'), findsOneWidget);
      verify(api.myTruckLoad()).called(2);
    });

    testWidgets('un refresh fallido se ve también en el estado vacío',
        (t) async {
      when(api.myTruckLoad())
          .thenAnswer((_) async => myLoad(open: false, require: true));
      await t.pumpWidget(app(const MyLoadView()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('my-load-refresh-error')), findsNothing);
      when(api.myTruckLoad()).thenThrow(offline());
      await t.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('my-load-refresh-error')), findsOneWidget);
      expect(find.text('Sin carga abierta'), findsOneWidget);
    });

    testWidgets('un refresh fallido con carga la conserva y avisa', (t) async {
      when(api.myTruckLoad()).thenAnswer((_) async => myLoad());
      await t.pumpWidget(app(const MyLoadView()));
      await t.pumpAndSettle();
      when(api.myTruckLoad()).thenThrow(offline());
      await t.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('my-load-refresh-error')), findsOneWidget);
      expect(find.text('Carga N° 12'), findsOneWidget);
    });

    test('si falla la primera lectura muestra el error para reintentar',
        () async {
      when(api.myTruckLoad()).thenThrow(offline());
      final m = MyLoadViewModel();
      await m.load();
      expect(m.loadError, isNotNull);
    });

    testWidgets('el menú tiene "Mi carga" y abre la pantalla', (t) async {
      await t.pumpWidget(app(Scaffold(
          drawer: DriverMenuDrawer(onLogout: () {}), body: const SizedBox())));
      t.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await t.pumpAndSettle();
      await t.tap(find.text('Mi carga'));
      await t.pumpAndSettle();
      verify(nav.navigateToMyLoadView()).called(1);
    });
  });

  group('GET /orders/available (por qué no recibe pedidos)', () {
    late MockApiClient client;
    late MockDriverAuthService auth;
    late DriverApiService svc;

    Response res(dynamic data) => Response(
        requestOptions: RequestOptions(path: ''), data: data, statusCode: 200);

    setUp(() {
      client = MockApiClient();
      auth = MockDriverAuthService();
      when(auth.token).thenAnswer((_) async => 'tok');
      svc = DriverApiService(api: client, auth: auth);
    });

    test('devuelve el mensaje del back cuando openLoadRequired', () async {
      for (final m in [kMsgSinCarga, kMsgSinSalir, kMsgDevuelta]) {
        when(client.get('orders/available?limit=1', 'tok'))
            .thenAnswer((_) async => res(availableBlocked(m)));
        expect(await svc.noOrdersReason(), m);
      }
    });

    test('null si puede recibir pedidos', () async {
      when(client.get('orders/available?limit=1', 'tok'))
          .thenAnswer((_) async => res({
                'orders': [],
                'total': 0,
                'limit': 1,
                'offset': 0,
                'openLoadRequired': false,
                'message': null,
              }));
      expect(await svc.noOrdersReason(), isNull);
    });

    test('sólo cuenta si el back marca openLoadRequired', () async {
      when(client.get('orders/available?limit=1', 'tok')).thenAnswer(
          (_) async =>
              res({'orders': [], 'openLoadRequired': false, 'message': 'x'}));
      expect(await svc.noOrdersReason(), isNull);
    });
  });

  group('Aviso de carga en el Inicio', () {
    Future<void> pumpHome(WidgetTester t, String? motivo,
        {double scale = 1}) async {
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      HomeView.debugMapBuilder = (_, __) => Container(color: Colors.grey);
      HomeView.debugViewModelFactory = () => _HomeConAviso(motivo);
      addTearDown(() {
        HomeView.debugMapBuilder = null;
        HomeView.debugViewModelFactory = null;
      });
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: const HomeView(),
      ));
      await t.pump(const Duration(milliseconds: 200));
    }

    for (final m in [kMsgSinCarga, kMsgSinSalir, kMsgDevuelta]) {
      testWidgets('visible con el motivo del back: $m', (t) async {
        await pumpHome(t, m);
        expect(find.text(m), findsOneWidget);
      });
    }

    testWidgets('oculto si puede recibir pedidos', (t) async {
      await pumpHome(t, null);
      expect(find.byKey(const Key('home-no-orders-notice')), findsNothing);
    });

    testWidgets('tocarlo abre Mi carga y al volver relee', (t) async {
      when(api.noOrdersReason()).thenAnswer((_) async => kMsgSinCarga);
      await pumpHome(t, kMsgSinCarga);
      await t.tap(find.byKey(const Key('home-no-orders-notice')));
      await t.pump();
      verify(nav.navigateToMyLoadView()).called(1);
      verify(api.noOrdersReason()).called(1);
    });

    testWidgets('con letra grande no tapa el menú ni el estado', (t) async {
      await pumpHome(t, kMsgSinSalir, scale: 2.5);
      final notice = t.getRect(find.byKey(const Key('home-no-orders-notice')));
      final menu = t.getRect(find.byKey(const Key('home-menu')));
      final status = t.getRect(find.byKey(const Key('home-status')));
      expect(notice.bottom, lessThanOrEqualTo(menu.top));
      expect(notice.bottom, lessThanOrEqualTo(status.top));
      // El botón de estado de splg-lib desborda por sí solo con letra enorme
      // (sin aviso también); acá se mide que el aviso no tape nada.
      t.takeException();
    });
  });

  group('HomeViewModel: motivo para no recibir pedidos', () {
    test('se prende con el texto del back y se va solo', () async {
      final m = HomeViewModel(isHomeVisible: () => true);
      when(api.noOrdersReason()).thenAnswer((_) async => kMsgSinCarga);
      await m.refreshNoOrdersReason();
      expect(m.noOrdersReason, kMsgSinCarga);

      when(api.noOrdersReason()).thenAnswer((_) async => kMsgSinSalir);
      await m.refreshNoOrdersReason();
      expect(m.noOrdersReason, kMsgSinSalir);

      when(api.noOrdersReason()).thenAnswer((_) async => null);
      await m.refreshNoOrdersReason();
      expect(m.noOrdersReason, isNull);
    });

    test('si la lectura falla conserva el último estado conocido', () async {
      final m = HomeViewModel(isHomeVisible: () => true);
      when(api.noOrdersReason()).thenAnswer((_) async => kMsgDevuelta);
      await m.refreshNoOrdersReason();
      when(api.noOrdersReason()).thenThrow(offline());
      await m.refreshNoOrdersReason();
      expect(m.noOrdersReason, kMsgDevuelta);
    });
  });

  group('HomeViewModel: sondeo del motivo', () {
    const every = Duration(seconds: 20);

    /// Arma el Inicio con `initialize()` de verdad (permisos mockeados).
    Future<HomeViewModel> started(WidgetTester t,
        {bool Function()? visible}) async {
      when(api.noOrdersReason()).thenAnswer((_) async => null);
      final m = HomeViewModel(
          loadPollInterval: every, isHomeVisible: visible ?? () => true);
      m.initialise();
      unawaited(m.initialize());
      await t.pump();
      clearInteractions(api);
      return m;
    }

    testWidgets('consulta cada intervalo mientras el Inicio está a la vista',
        (t) async {
      final m = await started(t);
      await t.pump(every);
      await t.pump(every);
      await t.pump(every);
      verify(api.noOrdersReason()).called(3);
      m.dispose();
    });

    testWidgets('la primera lectura es al abrir (initialize no es un no-op)',
        (t) async {
      when(api.noOrdersReason()).thenAnswer((_) async => kMsgSinCarga);
      final m =
          HomeViewModel(loadPollInterval: every, isHomeVisible: () => true);
      m.initialise();
      unawaited(m.initialize());
      await t.pump();
      expect(m.noOrdersReason, kMsgSinCarga);
      m.dispose();
    });

    testWidgets('en segundo plano no consulta y al volver relee y retoma',
        (t) async {
      final m = await started(t);
      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      await t.pump(every);
      await t.pump(every);
      await t.pump(every);
      verifyNever(api.noOrdersReason());

      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await t.pump();
      verify(api.noOrdersReason()).called(1);
      await t.pump(every);
      verify(api.noOrdersReason()).called(1);
      m.dispose();
    });

    testWidgets('inactive también pausa', (t) async {
      final m = await started(t);
      m.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await t.pump(every);
      await t.pump(every);
      verifyNever(api.noOrdersReason());
      m.dispose();
    });

    testWidgets('no consulta mientras el Inicio no está a la vista', (t) async {
      var visible = false;
      final m = await started(t, visible: () => visible);
      await t.pump(every);
      await t.pump(every);
      verifyNever(api.noOrdersReason());
      visible = true;
      await t.pump(every);
      verify(api.noOrdersReason()).called(1);
      m.dispose();
    });

    testWidgets('al volver a primer plano con otra pantalla encima no consulta',
        (t) async {
      final m = await started(t, visible: () => false);
      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await t.pump();
      verifyNever(api.noOrdersReason());
      m.dispose();
    });

    testWidgets('al cerrar el Inicio el sondeo se cancela', (t) async {
      final m = await started(t);
      m.dispose();
      await t.pump(every);
      await t.pump(every);
      verifyNever(api.noOrdersReason());
    });
  });

  group('422 de idempotencia en el reporte "no pagó"', () {
    test('texto propio sólo para el 422 de idempotencia', () {
      expect(actionErrorText(idempotency422()), kIdempotencyConflictText);
      expect(kIdempotencyConflictText,
          'Este reporte ya quedó registrado. No hace falta enviarlo de nuevo.');
      final otro = DioException(
          requestOptions: RequestOptions(path: ''),
          response: Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 422,
              data: {'message': 'Algo distinto'}));
      expect(isIdempotencyConflict(otro), false);
    });

    PaymentViewModel vm() =>
        PaymentViewModel(orderId: 'o1', trips: trips, payments: payments);

    test(
        'mensaje claro, refresca el pedido y ya no ofrece "Pago recibido" '
        '(el back lo rechazaría con 409)', () async {
      var reported = false;
      when(trips.order('o1')).thenAnswer((_) async => trip(
          status: 'delivered', paymentStatus: reported ? 'unpaid' : 'pending'));
      final m = vm();
      await m.load();
      expect(m.needsCashConfirmation, true);
      reported = true; // la primera llamada sí llegó al back
      when(payments.reportUnpaid('o1', note: anyNamed('note')))
          .thenThrow(idempotency422());
      await m.reportUnpaid(note: 'No estaba');
      expect(m.actionError, kIdempotencyConflictText);
      expect(m.submitting, false);
      verify(trips.order('o1')).called(2);
      expect(m.isUnpaid, true);
      expect(m.needsCashConfirmation, false);
      expect(m.confirmLabel, 'Continuar');
      expect(m.footerText, contains('Ya informaste que el cliente no pagó'));
      // Continuar sigue al cierre como impago, sin llamar a "Pago recibido".
      await m.confirm();
      verifyNever(payments.confirmReceived(any));
      verify(nav.replaceWithCompletedView(orderId: 'o1', unpaid: true))
          .called(1);
    });

    test('un 422 con el pedido todavía pendiente conserva los botones',
        () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      final m = vm();
      await m.load();
      when(payments.reportUnpaid('o1', note: anyNamed('note')))
          .thenThrow(idempotency422());
      await m.reportUnpaid(note: 'x');
      expect(m.needsCashConfirmation, true);
    });

    test('la clave del reporte se reusa sin respuesta y también tras 422',
        () async {
      final api = MockApiClient();
      final auth = MockDriverAuthService();
      when(auth.token).thenAnswer((_) async => 'tok');
      final repo = HttpPaymentRepository(api: api, auth: auth, enabled: true);
      final keys = <String>[];
      var n = 0;
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add((i.positionalArguments[3]
            as Map<String, String>)['Idempotency-Key']!);
        n++;
        if (n == 1) throw offline();
        if (n == 2) throw idempotency422();
        return Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 200,
            data: {
              'incident': {'incident_id': 'i1'}
            });
      });
      await expectLater(
          repo.reportUnpaid('o1', note: 'a'), throwsA(isA<DioException>()));
      await expectLater(
          repo.reportUnpaid('o1', note: 'a'), throwsA(isA<DioException>()));
      expect(keys[0], keys[1], reason: 'sin respuesta: misma clave');
      await repo.reportUnpaid('o1', note: 'b');
      expect(keys[2], keys[1],
          reason: 'tras el 422 no se inventa clave: sería otro reporte');
    });
  });
}
