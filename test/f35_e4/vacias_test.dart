import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';
import 'support.dart';

void main() {
  group('OrderLine: vacías', () {
    test(
        'sin los campos de F35 espera una vacía por unidad y no hay declaradas',
        () {
      final l = OrderLine.fromJson(item(k10, 'Garrafa 10kg', 3, f35: false));
      expect(l.gasCylinderId, k10);
      expect(l.containersCharged, 0);
      expect(l.emptiesExpected, 3);
      expect(l.emptiesReceived, isNull);
    });

    test('las esperadas nunca pasan de la cantidad ni bajan de 0', () {
      expect(
          OrderLine.fromJson(item(k10, 'Garrafa 10kg', 2, expected: 5))
              .emptiesExpected,
          2);
      expect(
          OrderLine.fromJson(item(k10, 'Garrafa 10kg', 2, expected: -1))
              .emptiesExpected,
          0);
    });

    test('lee lo que manda el back', () {
      final l = OrderLine.fromJson(
          item(k15, 'Garrafa 15kg', 3, charged: 1, received: 1));
      expect(l.containersCharged, 1);
      expect(l.emptiesExpected, 2);
      expect(l.emptiesReceived, 1);
    });

    test('el pedido viejo (sin gas_cylinder_id) sigue cargando', () {
      final t = trip();
      expect(t.lines.single.gasCylinderId, isNull);
      expect(t.lines.single.emptiesExpected, 2);
    });
  });

  group('TripService.declareEmpties', () {
    late MockApiClient api;
    late MockDriverAuthService auth;
    late TripService svc;

    setUp(() {
      registerServices();
      api = MockApiClient();
      auth = MockDriverAuthService();
      when(auth.token).thenAnswer((_) async => 'tok');
      svc = TripService(api: api, auth: auth);
    });
    tearDown(() => locator.reset());

    Response ok(dynamic data) => Response(
        requestOptions: RequestOptions(path: ''), data: data, statusCode: 200);
    String keyOf(Invocation i) =>
        (i.positionalArguments[3] as Map<String, String>)['Idempotency-Key']!;

    test('PATCH v2 con los ítems y devuelve el pedido del back', () async {
      final back = orderJson(status: 'out_for_delivery');
      back['order_items'] = [item(k10, 'Garrafa 10kg', 2, received: 1)];
      when(api.patch(any, any, any, any)).thenAnswer((_) async => ok(back));
      final o = await svc.declareEmpties('o1', {k15: 2, k10: 1});
      final call = verify(api.patch(captureAny, captureAny, 'tok', any))
        ..called(1);
      expect(call.captured[0], endsWith('/api/v2/orders/o1/empties'));
      expect(call.captured[1], {
        'items': [
          {'gasCylinderId': k10, 'emptiesReceived': 1},
          {'gasCylinderId': k15, 'emptiesReceived': 2},
        ]
      });
      expect(o.lines.single.emptiesReceived, 1);
    });

    test('con la red caída el reintento reusa la clave; otro valor, otra',
        () async {
      final keys = <String>[];
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add(keyOf(i));
        if (keys.length == 1) {
          throw DioException(requestOptions: RequestOptions(path: ''));
        }
        return ok(orderJson(status: 'out_for_delivery'));
      });
      await expectLater(
          svc.declareEmpties('o1', {k10: 1}), throwsA(isA<DioException>()));
      await svc.declareEmpties('o1', {k10: 1});
      await svc.declareEmpties('o1', {k10: 0});
      expect(keys[0], keys[1]);
      expect(keys[2], isNot(keys[1]));
    });
  });

  group('DeliveryViewModel: vacías', () {
    late MockTripService trips;
    late MockNavigationService nav;

    setUp(() {
      registerServices();
      trips = locator<TripService>() as MockTripService;
      nav = locator<NavigationService>() as MockNavigationService;
      when(trips.order('o1')).thenAnswer((_) async => tripWithEmpties());
      when(trips.customerRating('c1')).thenAnswer((_) async => null);
      when(trips.arrived('o1')).thenAnswer((_) async {});
    });
    tearDown(() => locator.reset());

    DeliveryViewModel build() => DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          pollInterval: const Duration(hours: 1),
          goHome: () {},
        );

    DioException rejected(int code, String msg) => DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: code,
            data: {'message': msg}));

    EmptiesRow row(DeliveryViewModel m, String id) =>
        m.emptiesRows.firstWhere((r) => r.gasCylinderId == id);

    test('precarga las esperadas por tipo y avisa los envases comprados',
        () async {
      final m = build();
      await m.initialize();
      expect(m.showEmpties, true);
      expect(m.emptiesRows.map((r) => r.gasCylinderId), [k10, k15]);
      expect(row(m, k10).expected, 2);
      expect(row(m, k10).value, 2);
      expect(row(m, k10).purchasedText, isNull);
      expect(row(m, k15).expected, 2);
      expect(row(m, k15).value, 2);
      expect(row(m, k15).purchasedText,
          'El cliente compró 1 envase: no devuelve vacía por ese.');
      expect(m.emptiesChanged, false);
      m.dispose();
    });

    test('si ya declaró, precarga lo declarado', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => tripWithEmpties(received10: 1));
      final m = build();
      await m.initialize();
      expect(row(m, k10).value, 1);
      expect(m.emptiesChanged, false);
      m.dispose();
    });

    test('aceptado (todavía no salió) no muestra la sección', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => tripWithEmpties(status: 'accepted'));
      final m = build();
      await m.initialize();
      expect(m.showEmpties, false);
      m.dispose();
    });

    test('el selector va de 0 a las esperadas', () async {
      final m = build();
      await m.initialize();
      m.addEmpty(k10);
      expect(row(m, k10).value, 2);
      m.removeEmpty(k10);
      m.removeEmpty(k10);
      m.removeEmpty(k10);
      expect(row(m, k10).value, 0);
      expect(row(m, k10).canRemove, false);
      expect(m.emptiesChanged, true);
      m.dispose();
    });

    test('sin cambios no llama al back y abre el QR', () async {
      final m = build();
      await m.initialize();
      await m.arriveAndDeliver();
      verifyNever(trips.declareEmpties(any, any));
      verify(nav.navigateToDeliveryQrView(orderId: 'o1')).called(1);
      m.dispose();
    });

    test(
        'si cambió, manda todas las vacías antes del QR y toma el pedido nuevo',
        () async {
      final calls = <String>[];
      when(trips.declareEmpties('o1', any)).thenAnswer((_) async {
        calls.add('empties');
        when(trips.order('o1'))
            .thenAnswer((_) async => tripWithEmpties(received10: 1));
        return tripWithEmpties(received10: 1);
      });
      when(nav.navigateToDeliveryQrView(orderId: 'o1'))
          .thenAnswer((_) async => calls.add('qr'));
      final m = build();
      await m.initialize();
      m.removeEmpty(k10);
      await m.arriveAndDeliver();
      verify(trips.declareEmpties('o1', {k10: 1, k15: 2})).called(1);
      expect(calls, ['empties', 'qr']);
      expect(row(m, k10).declared, 1);
      expect(m.emptiesChanged, false);
      m.dispose();
    });

    test('ya registrado, el selector sigue al back y no al borrador', () async {
      when(trips.declareEmpties('o1', any))
          .thenAnswer((_) async => tripWithEmpties(received10: 1));
      final m = build();
      await m.initialize();
      m.removeEmpty(k10);
      // Al volver del QR el back ya tiene otro valor (p. ej. lo corrigió).
      when(trips.order('o1'))
          .thenAnswer((_) async => tripWithEmpties(received10: 0));
      await m.arriveAndDeliver();
      expect(row(m, k10).value, 0);
      expect(m.emptiesChanged, false);
      m.dispose();
    });

    test('lo que el chofer movió sobrevive a una relectura del pedido',
        () async {
      final m = build();
      await m.initialize();
      m.removeEmpty(k15);
      when(nav.navigateToDeliveryQrView(orderId: 'o1'))
          .thenAnswer((_) async => null);
      // Volver del QR relee el pedido.
      await m.openDeliveryQr();
      expect(row(m, k15).value, 1);
      expect(m.emptiesChanged, true);
      m.dispose();
    });

    test(
        'si el back rechaza muestra su mensaje, no abre el QR y conserva lo '
        'cargado', () async {
      when(trips.declareEmpties('o1', any)).thenThrow(rejected(
          400, 'Las vacías recibidas no pueden superar las esperadas'));
      final m = build();
      await m.initialize();
      m.removeEmpty(k10);
      await m.arriveAndDeliver();
      expect(m.errorMessage,
          'Las vacías recibidas no pueden superar las esperadas');
      verifyNever(nav.navigateToDeliveryQrView(orderId: 'o1'));
      expect(row(m, k10).value, 1);
      expect(m.isUpdatingStatus, false);
      // El aviso de llegada ya salió: el reintento no lo repite.
      expect(m.arrivedNotified, true);
      when(trips.declareEmpties('o1', any))
          .thenAnswer((_) async => tripWithEmpties(received10: 1));
      await m.arriveAndDeliver();
      verify(trips.arrived('o1')).called(1);
      verify(nav.navigateToDeliveryQrView(orderId: 'o1')).called(1);
      m.dispose();
    });

    test('con 403 de otro chofer o 409 de otro estado tampoco avanza',
        () async {
      // El 403 se muestra con el texto fijo de `ApiErrorText` (convención de
      // la app); el 409 de negocio, con el mensaje del back.
      for (final (code, msg, shown) in [
        (403, 'El pedido no está asignado a vos', ApiErrorText.forbidden),
        (409, 'El pedido no está en camino', 'El pedido no está en camino'),
      ]) {
        when(trips.declareEmpties('o1', any)).thenThrow(rejected(code, msg));
        final m = build();
        await m.initialize();
        m.removeEmpty(k10);
        await m.arriveAndDeliver();
        expect(m.errorMessage, shown);
        m.dispose();
      }
      verifyNever(nav.navigateToDeliveryQrView(orderId: 'o1'));
    });

    test('doble toque: una sola llamada y no se mueve el selector en vuelo',
        () async {
      final gate = Completer<void>();
      when(trips.declareEmpties('o1', any)).thenAnswer((_) async {
        await gate.future;
        return tripWithEmpties(received10: 1);
      });
      final m = build();
      await m.initialize();
      m.removeEmpty(k10);
      final first = m.arriveAndDeliver();
      final second = m.arriveAndDeliver();
      await Future<void>.delayed(Duration.zero);
      m.removeEmpty(k10);
      expect(row(m, k10).value, 1);
      gate.complete();
      await Future.wait([first, second]);
      verify(trips.declareEmpties('o1', any)).called(1);
      verify(nav.navigateToDeliveryQrView(orderId: 'o1')).called(1);
      m.dispose();
    });
  });
}
