import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/payment_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery_qr/delivery_qr_viewmodel.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_driver/ui/views/payment/payment_viewmodel.dart';
import 'package:splg_driver/ui/views/pending_collections/pending_collections_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';
import 'support.dart';

DioException http(int code, [dynamic data]) => DioException(
    requestOptions: RequestOptions(path: ''),
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: code,
        data: data));

DioException gone() => http(410, {
      'statusCode': 410,
      'message': 'Este pedido ya no está asignado a tu usuario',
    });

DioException enCurso() => http(409, {
      'statusCode': 409,
      'message': 'Request en curso con la misma Idempotency-Key',
    });

DioException offline() =>
    DioException(requestOptions: RequestOptions(path: ''));

final DateTime _hoy = DateTime(2026, 10, 12, 15);

void main() {
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDialogService dialogs;
  late MockDriverSocketService socket;
  late MockDriverApiService api;
  late MockDriverAuthService auth;
  var homeCalls = 0;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    dialogs = locator<DialogService>() as MockDialogService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    api = locator<DriverApiService>() as MockDriverApiService;
    auth = locator<DriverAuthService>() as MockDriverAuthService;
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
    homeCalls = 0;
    when(trips.order('o1')).thenAnswer((_) async => trip());
    when(trips.customerRating(any)).thenAnswer((_) async => null);
    when(trips.deliveryCode('o1'))
        .thenAnswer((_) async => const DeliveryCodeInfo('A1B2C3D4E5'));
  });
  tearDown(() => locator.reset());

  group('H1. 410 / pedido que ya no es del chofer', () {
    DeliveryViewModel delivery() => DeliveryViewModel(
        orderId: 'o1',
        trips: trips,
        pollInterval: const Duration(milliseconds: 20),
        goHome: () => homeCalls++);

    void verificaLiberado() {
      verify(socket.stopTracking()).called(greaterThanOrEqualTo(1));
      verify(dialogs.showDialog(
              title: 'Pedido liberado', description: anyNamed('description')))
          .called(1);
      verify(trips.endFlow()).called(1);
      expect(homeCalls, 1);
    }

    test('el texto del 410 está en castellano', () {
      expect(actionErrorText(gone()), kOrderGoneText);
    });

    test('Entrega: un 410 al releer sale como pedido liberado', () async {
      final m = delivery();
      await m.initialize();
      when(trips.order('o1')).thenThrow(gone());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verificaLiberado();
      m.dispose();
    });

    test('Entrega: un 410 en la primera carga también', () async {
      when(trips.order('o1')).thenThrow(gone());
      final m = delivery();
      await m.initialize();
      verificaLiberado();
      expect(m.loadError, isNull);
      m.dispose();
    });

    test('Entrega: 404 de un pedido que ya tenía en pantalla es perdido',
        () async {
      final m = delivery();
      await m.initialize();
      when(trips.order('o1')).thenThrow(http(404, {'message': 'x'}));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verificaLiberado();
      m.dispose();
    });

    test('Entrega: 404 en la primera carga es un error de carga común',
        () async {
      when(trips.order('o1')).thenThrow(http(404, {'message': 'x'}));
      final m = delivery();
      await m.initialize();
      expect(m.loadError, isNotNull);
      expect(homeCalls, 0);
      m.dispose();
    });

    DeliveryQrViewModel qr() => DeliveryQrViewModel(
        orderId: 'o1',
        trips: trips,
        pollInterval: const Duration(milliseconds: 20),
        goHome: () => homeCalls++);

    test('QR: un 410 mientras espera la confirmación vuelve al Inicio',
        () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'on_the_way'));
      final m = qr();
      await m.initialize();
      when(trips.order('o1')).thenThrow(gone());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verificaLiberado();
      m.dispose();
    });

    test('QR: 403 del código de entrega tras reasignación es perdido',
        () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'on_the_way'));
      when(trips.deliveryCode('o1')).thenThrow(http(403, {'message': 'x'}));
      final m = qr();
      await m.initialize();
      verificaLiberado();
      expect(m.loadError, isNull);
      m.dispose();
    });

    test('QR: sin red sigue esperando (no es perdido)', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'on_the_way'));
      final m = qr();
      await m.initialize();
      when(trips.order('o1')).thenThrow(offline());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(homeCalls, 0);
      m.dispose();
    });
  });

  group('H2/H3. Claves de idempotencia', () {
    late MockApiClient client;
    late TripService svc;
    late HttpPaymentRepository repo;

    Response ok() => Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 201,
        data: <String, dynamic>{});
    String keyOf(Invocation i) =>
        (i.positionalArguments[3] as Map<String, String>)['Idempotency-Key']!;

    setUp(() {
      client = MockApiClient();
      svc = TripService(api: client, auth: auth);
      repo = HttpPaymentRepository(api: client, auth: auth, enabled: true);
    });

    for (final c in [
      ('409 en curso', enCurso),
      ('500', () => http(500, {'message': 'x'})),
      ('422 de clave ya usada', idempotency422),
    ]) {
      test('incidencia: ante ${c.$1} el reintento conserva la clave', () async {
        final keys = <String>[];
        when(client.post('incidents', any, any, any)).thenAnswer((i) async {
          keys.add(keyOf(i));
          if (keys.length == 1) throw c.$2();
          return ok();
        });
        await expectLater(svc.reportIncident('o1', 'damaged', 'rota'),
            throwsA(isA<DioException>()));
        await svc.reportIncident('o1', 'damaged', 'rota');
        expect(keys[0], keys[1]);
      });

      test('cobro: ante ${c.$1} el reintento conserva la clave', () async {
        final keys = <String>[];
        when(client.patch(any, any, any, any)).thenAnswer((i) async {
          keys.add(keyOf(i));
          if (keys.length == 1) throw c.$2();
          return Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: {
                'incident': {'incident_id': 'i1'}
              });
        });
        await expectLater(
            repo.reportUnpaid('o1', note: 'a'), throwsA(isA<DioException>()));
        await repo.reportUnpaid('o1', note: 'a');
        expect(keys[0], keys[1]);
      });
    }

    test('un rechazo de negocio (400) sí descarta la clave', () async {
      final keys = <String>[];
      when(client.post('incidents', any, any, any)).thenAnswer((i) async {
        keys.add(keyOf(i));
        if (keys.length == 1) throw http(400, {'message': 'El pedido no es'});
        return ok();
      });
      await expectLater(svc.reportIncident('o1', 'damaged', 'rota'),
          throwsA(isA<DioException>()));
      await svc.reportIncident('o1', 'damaged', 'rota');
      expect(keys[0], isNot(keys[1]));
    });

    test('H3: tras el 422 el cartel dice que ya quedó registrado', () {
      expect(kIdempotencyConflictText, contains('ya quedó registrado'));
      expect(kIdempotencyConflictText.toLowerCase(), isNot(contains('volvé')));
    });

    test('S1: los envases viajan en el mismo orden que la clave', () async {
      final bodies = <Map>[];
      when(client.post('cylinders/assign', any, any, any))
          .thenAnswer((i) async {
        bodies.add(i.positionalArguments[1] as Map);
        return ok();
      });
      await svc.assignCylinders('o1', ['B2', 'A1']);
      expect(bodies.single['serials'], ['A1', 'B2']);
    });
  });

  group('H4. "Más tarde" desde el flujo normal', () {
    test('no se reabre el cobro al volver de segundo plano', () async {
      final real = TripService(api: MockApiClient(), auth: auth);
      final home = HomeViewModel(trips: real, isHomeVisible: () => true)
        ..now = () => _hoy;
      DriverOrder p(DriverOrderStatus s) => DriverOrder(
          id: 'a',
          status: s,
          total: 1000,
          createdAt: DateTime(2026, 10, 1),
          deliveredAt: s == DriverOrderStatus.delivered ? _hoy : null,
          paymentMethod: 'cash',
          paymentStatus: 'pending');
      void pages(DriverOrder o) =>
          when(api.activeOrder()).thenAnswer((_) async => o);

      pages(p(DriverOrderStatus.accepted));
      final flow = home.resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(real.activeOrderId, 'a');

      // El cliente escaneó, el chofer llegó al Cobro y toca "Más tarde".
      PaymentViewModel(
              orderId: 'a',
              trips: real,
              payments: locator<PaymentRepository>() as MockPaymentRepository,
              goHome: () {})
          .later();
      await flow;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      pages(p(DriverOrderStatus.delivered));
      await home.resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(nav.navigateToPaymentView(orderId: 'a'));
    });
  });

  group('H5. Cobro', () {
    late MockPaymentRepository payments;
    setUp(() {
      payments = locator<PaymentRepository>() as MockPaymentRepository;
    });

    PaymentViewModel vm() =>
        PaymentViewModel(orderId: 'o1', trips: trips, payments: payments);

    test('un 409 al confirmar relee el pedido (el admin ya lo registró)',
        () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      final m = vm();
      await m.load();
      expect(m.needsCashConfirmation, true);
      when(payments.confirmReceived('o1'))
          .thenThrow(http(409, {'message': 'El pedido ya figura como impago'}));
      when(trips.order('o1')).thenAnswer(
          (_) async => trip(status: 'delivered', paymentStatus: 'unpaid'));
      await m.confirm();
      expect(m.actionError, isNotNull);
      expect(m.isUnpaid, true);
      expect(m.needsCashConfirmation, false);
    });

    for (final s in ['written_off', 'failed', 'unpaid', 'paid']) {
      test('efectivo en "$s" no es cobrable', () async {
        when(trips.order('o1')).thenAnswer(
            (_) async => trip(status: 'delivered', paymentStatus: s));
        final m = vm();
        await m.load();
        expect(m.needsCashConfirmation, false);
      });
    }
  });

  group('S2. Cobros pendientes', () {
    test('si se descartó mientras estaba el Cobro, no relee la lista',
        () async {
      final back = Completer<dynamic>();
      when(nav.navigateToPaymentView(orderId: 'a'))
          .thenAnswer((_) => back.future);
      final m = PendingCollectionsViewModel();
      final fut = m.open(DriverOrder(
          id: 'a',
          status: DriverOrderStatus.delivered,
          total: 1,
          createdAt: _hoy,
          paymentMethod: 'cash',
          paymentStatus: 'pending'));
      m.dispose();
      back.complete();
      await fut;
      verifyNever(api.orders());
    });
  });
}
