import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mockito/mockito.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:splg_driver/app/app.dialogs.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/fcm_service.dart';
import 'package:splg_driver/services/payment_repository.dart';
import 'package:splg_driver/services/photo_picker.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/common/navigation_helpers.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_driver/ui/views/login/login_viewmodel.dart';
import 'package:splg_driver/ui/views/payment/payment_view.dart';
import 'package:splg_driver/ui/views/payment/payment_viewmodel.dart';
import 'package:splg_driver/ui/views/pending_collections/pending_collections_view.dart';
import 'package:splg_driver/ui/widgets/driver_menu_drawer.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';
import 'support.dart';

final DateTime _hoy = DateTime(2026, 10, 12, 15);

/// Socket que nunca abre una conexión real: los tests de reconexión disparan los
/// cortes a mano y no dependen de la red ni de timers del cliente.
class _SocketMudo extends io.Socket {
  _SocketMudo(io.Socket base) : super(base.io, base.nsp, {});

  @override
  io.Socket connect() => this;
}

DriverOrder pedido(String id,
        {DriverOrderStatus status = DriverOrderStatus.delivered,
        String method = 'cash',
        String paymentStatus = 'pending',
        DateTime? deliveredAt,
        num total = 1000,
        num? remaining,
        bool depositPaid = false}) =>
    DriverOrder(
      id: id,
      status: status,
      total: total,
      createdAt: DateTime(2026, 10, 1),
      deliveredAt:
          status == DriverOrderStatus.delivered ? (deliveredAt ?? _hoy) : null,
      paymentMethod: method,
      paymentStatus: paymentStatus,
      remainingBalance: remaining,
      depositPaid: depositPaid,
    );

void main() {
  late MockDriverApiService api;
  late MockNavigationService nav;
  late MockTripService trips;
  late MockDriverAuthService auth;
  late MockDriverSocketService socket;
  late MockDialogService dialogs;

  setUp(() {
    registerServices();
    api = locator<DriverApiService>() as MockDriverApiService;
    nav = locator<NavigationService>() as MockNavigationService;
    trips = locator<TripService>() as MockTripService;
    auth = locator<DriverAuthService>() as MockDriverAuthService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    dialogs = locator<DialogService>() as MockDialogService;
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
  });
  tearDown(() => locator.reset());

  group('1. Socket: reconexión con backoff', () {
    late io.Socket created;

    DriverSocketService service({
      required Future<String?> Function() provider,
      DateTime Function()? now,
    }) =>
        DriverSocketService(
          tokenProvider: provider,
          now: now,
          random: Random(7),
          socketFactory: (uri, opts) => created = _SocketMudo(io.io(
              'http://localhost:1',
              {...opts, 'autoConnect': false, 'forceNew': true})),
        );

    test('la espera crece exponencialmente, con tope y jitter', () {
      final svc = service(provider: () async => 't');
      for (var i = 0; i < 40; i++) {
        final d0 = svc.backoff(0).inMilliseconds;
        final d3 = svc.backoff(3).inMilliseconds;
        final d30 = svc.backoff(30).inMilliseconds;
        expect(d0, inInclusiveRange(500, 1000));
        expect(d3, inInclusiveRange(4000, 8000));
        expect(d30, inInclusiveRange(30000, 60000));
      }
      final distintos = {for (var i = 0; i < 20; i++) svc.backoff(2)};
      expect(distintos.length, greaterThan(1), reason: 'hay jitter');
    });

    testWidgets(
        'un servidor que corta siempre no recibe una lluvia de conexiones',
        (t) async {
      var attempts = 0;
      var cuts = 0;
      final svc = service(provider: () async {
        attempts++;
        // El "servidor" corta cada conexión apenas se abre.
        if (cuts++ < 500) {
          scheduleMicrotask(() => created.onclose('io server disconnect'));
        }
        return 't';
      });
      svc.connect('t', 'd1');
      created.onclose('io server disconnect');
      await t.pump(const Duration(seconds: 3));
      expect(attempts, lessThanOrEqualTo(3));
      svc.disconnect();
    });

    testWidgets('tras varios cortes seguidos deja de insistir y avisa',
        (t) async {
      var attempts = 0;
      final svc = service(provider: () async {
        attempts++;
        scheduleMicrotask(() => created.onclose('io server disconnect'));
        return 't';
      });
      var avisos = 0;
      final sub = svc.rejected.listen((_) => avisos++);
      svc.connect('t', 'd1');
      created.onclose('io server disconnect');
      await t.pump(const Duration(minutes: 5));
      expect(avisos, 1);
      final intentos = attempts;
      expect(intentos, lessThan(DriverSocketService.maxServerCuts));
      await t.pump(const Duration(minutes: 5));
      expect(attempts, intentos, reason: 'no reintenta después de renunciar');
      unawaited(sub.cancel());
      svc.disconnect();
    });

    testWidgets('con el acceso revocado no reintenta y avisa al toque',
        (t) async {
      var attempts = 0;
      final svc = service(provider: () async {
        attempts++;
        return 't';
      });
      var avisos = 0;
      final sub = svc.rejected.listen((_) => avisos++);
      svc.connect('t', 'd1');
      created.emitReserved('server:access-revoked', {'motivo': 'bloqueo'});
      created.onclose('io server disconnect');
      await t.pump(const Duration(minutes: 5));
      expect(avisos, 1);
      expect(attempts, 0);
      unawaited(sub.cancel());
      svc.disconnect();
    });

    testWidgets('el aviso del cambio de dirección sale por su stream',
        (t) async {
      final svc = service(provider: () async => 't');
      final avisos = <Map<String, dynamic>>[];
      final sub = svc.orderAddressChanged.listen(avisos.add);
      svc.connect('t', 'd1');
      created.emitReserved('order:address-changed', {'orderId': 'o1'});
      created.emitReserved('order:address-changed', 'basura');
      await t.pump();
      expect(avisos, [
        {'orderId': 'o1'}
      ]);
      unawaited(sub.cancel());
      svc.disconnect();
    });

    testWidgets('una conexión estable reinicia la cuenta de cortes', (t) async {
      var ahora = DateTime(2026, 1, 1);
      final svc = service(provider: () async => 't', now: () => ahora);
      var avisos = 0;
      final sub = svc.rejected.listen((_) => avisos++);
      svc.connect('t', 'd1');
      for (var i = 0; i < DriverSocketService.maxServerCuts - 1; i++) {
        created.onclose('io server disconnect');
      }
      // Se conecta y aguanta más de lo que se considera un rechazo.
      created.emitReserved('connect');
      ahora = ahora.add(DriverSocketService.stableAfter);
      for (var i = 0; i < DriverSocketService.maxServerCuts - 1; i++) {
        created.onclose('io server disconnect');
        await t.pump();
      }
      expect(avisos, 0);
      created.onclose('io server disconnect');
      await t.pump();
      expect(avisos, 1);
      unawaited(sub.cancel());
      svc.disconnect();
    });

    test('un corte que no es del servidor lo reintenta el propio cliente',
        () async {
      var llamadas = 0;
      final svc = service(provider: () async {
        llamadas++;
        return 't';
      });
      svc.connect('t', 'd1');
      created.onclose('transport close');
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(llamadas, 0);
      svc.disconnect();
    });

    HomeViewModel enLinea(StreamController<void> rechazos) {
      when(socket.rejected).thenAnswer((_) => rechazos.stream);
      when(socket.isConnected).thenReturn(false);
      when(socket.hasSocket).thenReturn(false);
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
      when(socket.incomingOrders)
          .thenAnswer((_) => const Stream<Map<String, dynamic>>.empty());
      final client = MockApiClient();
      when(client.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      return HomeViewModel(trips: trips, apiClient: client);
    }

    test('el Inicio baja al chofer de línea y avisa si el servidor lo rechaza',
        () async {
      final rechazos = StreamController<void>.broadcast();
      final m = enLinea(rechazos);
      await m.connect();
      rechazos.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verify(socket.disconnect()).called(greaterThan(0));
      verify(dialogs.showDialog(
              title: 'Se cortó tu conexión',
              description: anyNamed('description')))
          .called(1);
      await rechazos.close();
    });

    test('si la distribuidora le cortó el acceso, el aviso lo dice', () async {
      final rechazos = StreamController<void>.broadcast();
      final m = enLinea(rechazos);
      when(socket.accessRevoked).thenReturn(true);
      await m.connect();
      rechazos.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verify(dialogs.showDialog(
              title: 'Tu cuenta no está habilitada',
              description: anyNamed('description')))
          .called(1);
      await rechazos.close();
    });
  });

  group('2. El Inicio sabe si está al frente (pila real)', () {
    Future<void> pumpApp(WidgetTester t) async {
      when(api.noOrdersReason()).thenAnswer((_) async => kMsgSinCarga);
      HomeView.debugMapBuilder = (_, __) => Container(color: Colors.grey);
      HomeView.debugViewModelFactory =
          () => HomeViewModel(loadPollInterval: const Duration(seconds: 20));
      addTearDown(() {
        HomeView.debugMapBuilder = null;
        HomeView.debugViewModelFactory = null;
      });
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        navigatorObservers: [appRouteObserver],
        home: const Scaffold(body: Text('Bienvenida')),
      ));
      final nav = Navigator.of(t.element(find.text('Bienvenida')));
      // Bienvenida -> Login -> (login ok) Inicio con la pila limpia.
      nav.push(MaterialPageRoute(builder: (_) => const Text('Login')));
      await t.pumpAndSettle();
      nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeView()), (_) => false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      clearInteractions(api);
    }

    testWidgets('consulta cada intervalo después de iniciar sesión', (t) async {
      await pumpApp(t);
      await t.pump(const Duration(seconds: 20));
      await t.pump(const Duration(seconds: 20));
      verify(api.noOrdersReason()).called(2);
    });

    testWidgets('con otra pantalla encima no consulta y al volver relee',
        (t) async {
      await pumpApp(t);
      final nav = Navigator.of(t.element(find.byType(HomeView)));
      nav.push(MaterialPageRoute(builder: (_) => const Text('Mi carga')));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 20));
      await t.pump(const Duration(seconds: 20));
      verifyNever(api.noOrdersReason());
      nav.pop();
      await t.pumpAndSettle();
      verify(api.noOrdersReason()).called(1);
      await t.pump(const Duration(seconds: 20));
      verify(api.noOrdersReason()).called(1);
    });

    test('el login deja la pila limpia con el Inicio', () async {
      final fcm = locator<FcmService>() as MockFcmService;
      when(fcm.registerForCurrentUser(any,
              interactive: anyNamed('interactive')))
          .thenAnswer((_) async {});
      when(auth.signIn(any, any)).thenAnswer((_) async => true);
      final m = LoginViewModel()
        ..formValueMap['email'] = 'a@b.com'
        ..formValueMap['password'] = 'x';
      await m.onLogin();
      verify(nav.clearStackAndShow(Routes.homeView)).called(1);
      verifyNever(nav.replaceWithHomeView());
    });
  });

  group('3. Retomar el cobro: sólo el último de hoy, con salida', () {
    HomeViewModel home() =>
        HomeViewModel(trips: trips, isHomeVisible: () => true)
          ..now = () => _hoy;

    void pages(List<DriverOrder> orders) {
      when(api.activeOrder())
          .thenAnswer((_) async => orders.isEmpty ? null : orders.first);
    }

    test('abre el cobro del pedido que devuelve el back', () async {
      pages([
        pedido('ultimo', deliveredAt: _hoy.subtract(const Duration(hours: 1))),
      ]);
      await home().resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(nav.navigateToPaymentView(orderId: 'ultimo')).called(1);
    });

    test('al terminar ese cobro no encadena el siguiente', () async {
      pages([
        pedido('a', deliveredAt: _hoy.subtract(const Duration(hours: 1))),
        pedido('b', deliveredAt: _hoy.subtract(const Duration(hours: 2))),
      ]);
      await home().resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(nav.navigateToPaymentView(orderId: 'a')).called(1);
      verifyNever(nav.navigateToPaymentView(orderId: 'b'));
    });

    test('los de días anteriores no se retoman solos', () async {
      pages([
        pedido('ayer', deliveredAt: _hoy.subtract(const Duration(days: 1)))
      ]);
      await home().resumeActiveOrder();
      verifyNever(nav.navigateToPaymentView(orderId: 'ayer'));
    });

    test('lo que dejó "Más tarde" no se vuelve a abrir en la sesión', () async {
      final real = TripService(api: MockApiClient(), auth: auth);
      final m = HomeViewModel(trips: real, isHomeVisible: () => true)
        ..now = () => _hoy;
      pages([pedido('a', status: DriverOrderStatus.accepted)]);
      final flow = m.resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      PaymentViewModel(
              orderId: 'a',
              trips: real,
              payments: locator<PaymentRepository>() as MockPaymentRepository,
              goHome: () {})
          .later();
      await flow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      pages([pedido('a')]);
      await m.resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(nav.navigateToPaymentView(orderId: 'a'));
    });

    test('un cobro retomado y dejado para después tampoco se reabre', () async {
      pages([pedido('a')]);
      final m = home();
      await m.resumeActiveOrder();
      await m.resumeActiveOrder();
      verify(nav.navigateToPaymentView(orderId: 'a')).called(1);
    });

    PaymentViewModel vm({void Function()? goHome}) => PaymentViewModel(
        orderId: 'o1',
        trips: trips,
        payments: locator<PaymentRepository>() as MockPaymentRepository,
        goHome: goHome ?? () {});

    test('"Más tarde" libera el Inicio y vuelve sin registrar nada', () {
      var volvio = 0;
      final payments = locator<PaymentRepository>() as MockPaymentRepository;
      vm(goHome: () => volvio++).later();
      verify(trips.endFlow()).called(1);
      expect(volvio, 1);
      verifyNever(payments.confirmReceived(any));
      verifyNever(payments.reportUnpaid(any, note: anyNamed('note')));
    });

    testWidgets('el botón "Más tarde" avisa y vuelve', (t) async {
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      var volvio = 0;
      PaymentView.debugViewModelFactory = (id) => vm(goHome: () => volvio++);
      addTearDown(() => PaymentView.debugViewModelFactory = null);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme, home: const PaymentView(orderId: 'o1')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byKey(const Key('payment-later')));
      await t.pump();
      expect(volvio, 1);
      expect(find.textContaining('Cobros pendientes'), findsOneWidget);
    });

    testWidgets('si el pedido no carga también hay salida', (t) async {
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      when(trips.order('o1'))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '')));
      var volvio = 0;
      PaymentView.debugViewModelFactory = (id) => vm(goHome: () => volvio++);
      addTearDown(() => PaymentView.debugViewModelFactory = null);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme, home: const PaymentView(orderId: 'o1')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('payment-error')), findsOneWidget);
      await t.tap(find.byKey(const Key('payment-later')));
      await t.pump();
      expect(volvio, 1);
      verify(trips.endFlow()).called(1);
    });

    testWidgets('"Cobros pendientes": lista sólo los efectivos sin cobrar',
        (t) async {
      when(api.orders()).thenAnswer((_) async => [
            pedido('a', total: 5000),
            pedido('b', paymentStatus: 'paid'),
            pedido('c', method: 'online'),
            pedido('d', status: DriverOrderStatus.cancelled),
            pedido('e', total: 31900, remaining: 22330, depositPaid: true),
          ]);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme, home: const PendingCollectionsView()));
      await t.pumpAndSettle();
      expect(find.text(formatMoney(5000)), findsOneWidget);
      expect(find.text(formatMoney(22330)), findsOneWidget);
      expect(find.byType(SplgListRow), findsNWidgets(2));
      await t.tap(find.text(formatMoney(5000)));
      await t.pumpAndSettle();
      verify(nav.navigateToPaymentView(orderId: 'a')).called(1);
    });

    testWidgets('sin pendientes: todo cobrado', (t) async {
      when(api.orders())
          .thenAnswer((_) async => [pedido('b', paymentStatus: 'paid')]);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme, home: const PendingCollectionsView()));
      await t.pumpAndSettle();
      expect(find.text('Todo cobrado'), findsOneWidget);
    });

    testWidgets('el menú tiene "Cobros pendientes"', (t) async {
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
              drawer: DriverMenuDrawer(onLogout: () {}),
              body: const SizedBox())));
      t.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await t.pumpAndSettle();
      await t.tap(find.text('Cobros pendientes'));
      await t.pumpAndSettle();
      verify(nav.navigateToPendingCollectionsView()).called(1);
    });
  });

  group('4. Una sola cifra para lo cobrado', () {
    test('las estadísticas suman el saldo cuando hubo seña paga', () {
      final orders = [
        pedido('a', total: 31900, remaining: 22330, depositPaid: true),
        pedido('b', total: 1000),
      ];
      final s = EarningsSummary.from(orders, _hoy);
      expect(s.today, 23330);
      expect(s.total, 23330);
      expect(s.month, 23330);
      expect(s.lastSevenDays.last, 23330);
    });

    test('el pedido del historial lee seña y saldo del back', () {
      final o = DriverOrder.fromJson({
        'order_id': 'o1',
        'status': 'delivered',
        'total_amount': 31900,
        'created_at': '2026-10-12T10:00:00.000Z',
        'depositAmount': 9570,
        'depositPaid': true,
        'remainingBalance': 22330,
      });
      expect(o.amountToCollect, 22330);
      expect(
          DriverOrder.fromJson({
            'order_id': 'o2',
            'status': 'delivered',
            'total_amount': 500,
            'created_at': '2026-10-12T10:00:00.000Z',
          }).amountToCollect,
          500);
      expect(
          DriverOrder.fromJson({
            'order_id': 'o3',
            'status': 'delivered',
            'total_amount': 31900,
            'created_at': '2026-10-12T10:00:00.000Z',
            'depositPaid': false,
            'remainingBalance': 22330,
          }).amountToCollect,
          31900);
    });
  });

  group('5. Foto: una sola copia, sin dejar archivos', () {
    Uint8List jpeg() {
      final image = img.Image(width: 40, height: 20);
      image.exif.imageIfd.make = 'MARCA-SECRETA';
      return Uint8List.fromList(img.encodeJpg(image));
    }

    Future<File> temp() async {
      final dir = await Directory.systemTemp.createTemp('foto_android');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/original.jpg');
      await f.writeAsBytes(jpeg());
      return f;
    }

    test('en Android pide la original sin escalar y la reduce acá', () async {
      final f = await temp();
      final fake = _RecordingPicker(f.path);
      final out =
          await ImagePickerPhotoPicker(picker: fake, scaleBySystem: false)
              .pick(PhotoSource.gallery);
      expect(fake.maxWidth, isNull);
      expect(fake.imageQuality, isNull);
      expect(String.fromCharCodes(out!).contains('MARCA-SECRETA'), false);
      expect(f.existsSync(), false);
    });

    test('en iOS deja que el sistema escale (y recodifique HEIC a JPEG)',
        () async {
      final f = await temp();
      final fake = _RecordingPicker(f.path);
      await ImagePickerPhotoPicker(picker: fake, scaleBySystem: true)
          .pick(PhotoSource.camera);
      expect(fake.maxWidth, 1280);
      expect(fake.imageQuality, 70);
    });

    test('la orientación EXIF se aplica igual sin bakeOrientation', () async {
      final image = img.Image(width: 40, height: 20);
      image.exif.imageIfd.orientation = 6;
      final out = await ImagePickerPhotoPicker.sanitize(
          Uint8List.fromList(img.encodeJpg(image)));
      final d = img.decodeImage(out)!;
      expect([d.width, d.height], [20, 40]);
    });
  });

  group('6. Claves de idempotencia por intención', () {
    late MockApiClient client;
    late TripService svc;
    String keyOf(Invocation i) =>
        (i.positionalArguments[3] as Map<String, String>)['Idempotency-Key']!;

    setUp(() {
      client = MockApiClient();
      final a = MockDriverAuthService();
      when(a.token).thenAnswer((_) async => 'tok');
      svc = TripService(api: client, auth: a);
    });

    Response ok() => Response(
        requestOptions: RequestOptions(path: ''), statusCode: 201, data: {});

    test('incidencias de distinto tipo no comparten clave', () async {
      final keys = <String, String>{};
      var n = 0;
      when(client.post('incidents', any, any, any)).thenAnswer((i) async {
        keys['${n++}'] = keyOf(i);
        throw DioException(requestOptions: RequestOptions(path: ''));
      });
      for (final tipo in ['damaged', 'no_show', 'damaged']) {
        await expectLater(
            svc.reportIncident('o1', tipo, 'x'), throwsA(isA<DioException>()));
      }
      expect(keys['0'], isNot(keys['1']));
      expect(keys['0'], keys['2'], reason: 'mismo tipo sin respuesta: igual');
    });

    test('despachar otros envases usa otra clave', () async {
      final keys = <String>[];
      when(client.post('cylinders/assign', any, any, any))
          .thenAnswer((i) async {
        keys.add(keyOf(i));
        throw DioException(requestOptions: RequestOptions(path: ''));
      });
      for (final s in [
        ['A1'],
        ['A2'],
        ['A1']
      ]) {
        await expectLater(
            svc.assignCylinders('o1', s), throwsA(isA<DioException>()));
      }
      expect(keys[0], isNot(keys[1]));
      expect(keys[0], keys[2]);
      when(client.post('cylinders/assign', any, any, any))
          .thenAnswer((_) async => ok());
    });
  });

  group('7. Carreras del Inicio', () {
    test('una respuesta vieja y lenta no pisa a la más nueva', () async {
      final m = HomeViewModel(isHomeVisible: () => true);
      final lenta = Completer<String?>();
      when(api.noOrdersReason()).thenAnswer((_) => lenta.future);
      final primera = m.refreshNoOrdersReason();
      when(api.noOrdersReason()).thenAnswer((_) async => null);
      await m.refreshNoOrdersReason();
      expect(m.noOrdersReason, isNull);
      lenta.complete(kMsgSinCarga);
      await primera;
      expect(m.noOrdersReason, isNull);
    });

    String? activo;

    HomeViewModel enLinea(StreamController<Map<String, dynamic>> ofertas) {
      when(socket.isConnected).thenReturn(false);
      when(socket.hasSocket).thenReturn(false);
      when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
      when(socket.incomingOrders).thenAnswer((_) => ofertas.stream);
      activo = null;
      when(trips.activeOrderId).thenAnswer((_) => activo);
      when(trips.beginFlow(any)).thenAnswer((i) {
        activo = i.positionalArguments.first as String;
      });
      final client = MockApiClient();
      when(client.patch(any, any, any)).thenAnswer(
          (_) async => Response(requestOptions: RequestOptions(path: '')));
      return HomeViewModel(trips: trips, apiClient: client)..now = () => _hoy;
    }

    test(
        'una oferta que llega mientras se busca un pedido retomado espera la '
        'decisión', () async {
      final ofertas = StreamController<Map<String, dynamic>>.broadcast();
      final pagina = Completer<DriverOrder?>();
      when(api.activeOrder()).thenAnswer((_) => pagina.future);
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async => DialogResponse(confirmed: false));
      final m = enLinea(ofertas);
      await m.connect();
      ofertas.add({'orderId': 'oferta', 'event': 'NEW_ORDER'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verifyNever(dialogs.showCustomDialog(
          variant: anyNamed('variant'),
          data: anyNamed('data'),
          barrierDismissible: anyNamed('barrierDismissible')));
      // Había un pedido en curso: se retoma y la oferta se rechaza por ocupado.
      pagina.complete(pedido('curso', status: DriverOrderStatus.accepted));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(nav.navigateToDeliveryView(orderId: 'curso')).called(1);
      verify(trips.reject('oferta')).called(1);
      verifyNever(dialogs.showCustomDialog(
          variant: anyNamed('variant'),
          data: anyNamed('data'),
          barrierDismissible: anyNamed('barrierDismissible')));
      await ofertas.close();
    });

    test('si no había nada que retomar la oferta se muestra', () async {
      final ofertas = StreamController<Map<String, dynamic>>.broadcast();
      final pagina = Completer<OrdersPage>();
      when(api.ordersPage(offset: anyNamed('offset'), limit: anyNamed('limit')))
          .thenAnswer((_) => pagina.future);
      when(dialogs.showCustomDialog(
              variant: anyNamed('variant'),
              data: anyNamed('data'),
              barrierDismissible: anyNamed('barrierDismissible')))
          .thenAnswer((_) async => DialogResponse(confirmed: false));
      final m = enLinea(ofertas);
      await m.connect();
      ofertas.add({'orderId': 'oferta', 'event': 'NEW_ORDER'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      pagina.complete(const OrdersPage(orders: [], total: 0, offset: 0));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(dialogs.showCustomDialog(
              variant: DialogType.orderOffer,
              data: anyNamed('data'),
              barrierDismissible: false))
          .called(1);
      await ofertas.close();
    });
  });
}

class _RecordingPicker extends ImagePicker {
  _RecordingPicker(this.path);

  final String path;
  double? maxWidth;
  int? imageQuality;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.maxWidth = maxWidth;
    this.imageQuality = imageQuality;
    return XFile(path);
  }
}
