import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/order_history.dart';
import 'package:splg_driver/models/truck_load.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/delivery/delivery_view.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery_detail/delivery_detail_view.dart';
import 'package:splg_driver/ui/views/delivery_detail/delivery_detail_viewmodel.dart';
import 'package:splg_driver/ui/views/my_load/my_load_view.dart';
import 'package:splg_driver/ui/views/my_load/my_load_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../mi_carga/support.dart';
import '../tanda3/support.dart';

Response<dynamic> _res(Object? data, [int status = 200]) => Response(
    requestOptions: RequestOptions(path: ''), data: data, statusCode: status);

/// Rechazo del back con la forma real de sus errores.
DioException _http(int code, String message) => DioException(
    requestOptions: RequestOptions(path: ''),
    type: DioExceptionType.badResponse,
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: code,
        data: {'statusCode': code, 'message': message}));

DioException _offline() => DioException(
    requestOptions: RequestOptions(path: ''),
    type: DioExceptionType.connectionError);

/// La carga de la demo con otro estado (`TruckLoadResponseDto`).
Map<String, dynamic> _loadJson(String status) =>
    {...myLoadJson()['load'] as Map<String, dynamic>, 'status': status};

TruckLoad _load(String status) => TruckLoad.fromJson(_loadJson(status));

MyTruckLoad _mine(String status) =>
    MyTruckLoad(load: _load(status), requireOpenTruckLoad: true);

// Mensajes reales del back (probados contra la API corriendo).
const _kEnRuta = 'La carga N° 4 está en ruta: no se puede confirmar la salida';
const _kPedidosEnCurso =
    'Tenés 1 pedido en curso: entregalos o liberalos antes de volver';
const _kFinalizado = 'No se puede cancelar un pedido finalizado';
const _kNoAsignado = 'Este pedido no está asignado a tu usuario';

void main() {
  group('Servicios contra el contrato del back', () {
    late MockApiClient api;
    late MockDriverAuthService auth;

    setUp(() {
      api = MockApiClient();
      auth = MockDriverAuthService();
      when(auth.userId).thenReturn('u1');
      when(auth.token).thenAnswer((_) async => 'tok');
    });

    String keyOf(Invocation i) =>
        (i.positionalArguments[3] as Map<String, String>)['Idempotency-Key']!;

    test(
        'salida: PATCH truck-loads/:id/depart con Idempotency-Key y lee la '
        'carga que devuelve', () async {
      final repo = HttpDriverOpsRepository(api: api, auth: auth);
      when(api.patch('truck-loads/l1/depart', {}, 'tok', any))
          .thenAnswer((_) async => _res(_loadJson('on_route')));
      final l = await repo.departTruckLoad('l1');
      expect(l.status, TruckLoadStatus.onRoute);
      expect(l.items.single.gasCylinderId, 'g1');
      final h =
          verify(api.patch('truck-loads/l1/depart', {}, 'tok', captureAny))
              .captured
              .single as Map<String, String>;
      expect(h['Idempotency-Key'], isNotEmpty);
    });

    test('salida: sin respuesta reusa la clave; con un 409 la descarta',
        () async {
      final repo = HttpDriverOpsRepository(api: api, auth: auth);
      final keys = <String>[];
      var n = 0;
      when(api.patch('truck-loads/l1/depart', {}, 'tok', any))
          .thenAnswer((i) async {
        keys.add(keyOf(i));
        n++;
        if (n == 1) throw _offline();
        if (n == 2) throw _http(409, _kEnRuta);
        return _res(_loadJson('on_route'));
      });
      await expectLater(
          repo.departTruckLoad('l1'), throwsA(isA<DioException>()));
      await expectLater(
          repo.departTruckLoad('l1'), throwsA(isA<DioException>()));
      await repo.departTruckLoad('l1');
      expect(keys[0], keys[1], reason: 'sin respuesta se reusa la clave');
      expect(keys[2], isNot(keys[1]), reason: 'el 409 la descarta');
    });

    test(
        'regreso: PATCH truck-loads/:id/return con todas las garrafas y sin '
        'Idempotency-Key (el back no la toma)', () async {
      final repo = HttpDriverOpsRepository(api: api, auth: auth);
      when(api.patch('truck-loads/l1/return', any, 'tok'))
          .thenAnswer((_) async => _res(_loadJson('returned')));
      final l = await repo.returnTruckLoad('l1', const [
        ReturnDeclaration(
            gasCylinderId: 'g1', declaredFull: 3, declaredEmpty: 38),
        ReturnDeclaration(
            gasCylinderId: 'g2', declaredFull: 0, declaredEmpty: 0),
      ]);
      expect(l.status, TruckLoadStatus.returned);
      final c = verify(api.patch('truck-loads/l1/return', captureAny, 'tok'))
          .captured
          .single;
      expect(c, {
        'items': [
          {'gasCylinderId': 'g1', 'declaredFull': 3, 'declaredEmpty': 38},
          {'gasCylinderId': 'g2', 'declaredFull': 0, 'declaredEmpty': 0},
        ]
      });
    });

    test(
        'liberar: PATCH orders/:id/cancel sin motivo, con Idempotency-Key '
        'reusada sin respuesta y descartada con un rechazo', () async {
      final svc = TripService(api: api, auth: auth);
      final keys = <String>[];
      var n = 0;
      when(api.patch('orders/o1/cancel', {}, 'tok', any)).thenAnswer((i) async {
        keys.add(keyOf(i));
        n++;
        if (n == 1) throw _offline();
        if (n == 2) throw _http(400, _kFinalizado);
        return _res(<String, dynamic>{});
      });
      await expectLater(svc.release('o1'), throwsA(isA<DioException>()));
      await expectLater(svc.release('o1'), throwsA(isA<DioException>()));
      await svc.release('o1');
      expect(keys[0], keys[1]);
      expect(keys[2], isNot(keys[1]));
    });

    test('incidencias: GET incidents/order/:id con la forma del back',
        () async {
      final svc = DriverApiService(api: api, auth: auth);
      when(api.get('incidents/order/o1', 'tok')).thenAnswer((_) async => _res([
            {
              'incident_id': 'i1',
              'order_id': 'o1',
              'distributor_id': 'd1',
              'reported_by': 'u1',
              'type': 'unpaid_collection',
              'description': 'El cliente no tenia efectivo',
              'photo_url': null,
              'status': 'resolved',
              'resolution_note': 'Pagó por transferencia',
              'createdAt': '2026-10-31T20:53:39.447Z',
              'resolvedAt': '2026-11-01T10:00:00.000Z',
            }
          ]));
      final i = (await svc.orderIncidents('o1')).single;
      expect(i.typeLabel, 'Cobro impago');
      expect(i.status, IncidentStatus.resolved);
      expect(i.resolutionNote, 'Pagó por transferencia');
      expect(i.resolvedAt, isNotNull);
    });

    test('historial: GET orders/:id/status-history con alta, cambios y notas',
        () async {
      final svc = DriverApiService(api: api, auth: auth);
      when(api.get('orders/o1/status-history', 'tok'))
          .thenAnswer((_) async => _res([
                {
                  'id': 'h1',
                  'fromStatus': null,
                  'toStatus': 'pending',
                  'isNote': false,
                  'reason': null,
                  'changedAt': '2026-11-02T13:18:42.144Z',
                  'changedBy': {
                    'userId': 'c1',
                    'role': 'customer',
                    'fullName': null
                  },
                },
                {
                  'id': 'h2',
                  'fromStatus': 'accepted',
                  'toStatus': 'out_for_delivery',
                  'isNote': false,
                  'reason': null,
                  'changedAt': '2026-11-02T17:45:54.714Z',
                  'changedBy': {
                    'userId': 'u1',
                    'role': 'delivery',
                    'fullName': null
                  },
                },
                {
                  'id': 'h3',
                  'fromStatus': 'delivered',
                  'toStatus': 'delivered',
                  'isNote': true,
                  'reason': 'Cobro en efectivo registrado',
                  'changedAt': '2026-11-02T18:00:00.000Z',
                  'changedBy': null,
                },
              ]));
      final h = await svc.orderStatusHistory('o1');
      expect(
          h.map((c) => c.title), ['Pendiente', 'Aceptado → En camino', 'Nota']);
      expect(h.map((c) => c.actorLabel), ['Cliente', 'Chofer', 'Sistema']);
      expect(h.last.reason, 'Cobro en efectivo registrado');
    });
  });

  group('ViewModels', () {
    late MockDriverApiService api;
    late MockDriverOpsRepository ops;
    late MockTripService trips;
    late MockDialogService dialogs;
    late MockDriverSocketService socket;

    setUp(() {
      registerServices();
      api = locator<DriverApiService>() as MockDriverApiService;
      ops = locator<DriverOpsRepository>() as MockDriverOpsRepository;
      trips = locator<TripService>() as MockTripService;
      dialogs = locator<DialogService>() as MockDialogService;
      socket = locator<DriverSocketService>() as MockDriverSocketService;
      final auth = locator<DriverAuthService>() as MockDriverAuthService;
      when(auth.token).thenAnswer((_) async => 'tok');
      when(auth.userId).thenReturn('u1');
    });
    tearDown(() => locator.reset());

    group('Mi carga: salida del camión', () {
      test('con éxito queda en ruta con lo que devuelve el back', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('loading'));
        when(ops.departTruckLoad('l1'))
            .thenAnswer((_) async => _load('on_route'));
        final m = MyLoadViewModel();
        await m.load();
        expect(m.openLoad!.canDepart, isTrue);
        expect(await m.depart(), isTrue);
        expect(m.openLoad!.status, TruckLoadStatus.onRoute);
        expect(m.requiresOpenLoad, isTrue);
        expect(m.acting, isFalse);
        expect(m.actionError, isNull);
      });

      test('doble toque: una sola llamada', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('loading'));
        final c = Completer<TruckLoad>();
        when(ops.departTruckLoad('l1')).thenAnswer((_) => c.future);
        final m = MyLoadViewModel();
        await m.load();
        final first = m.depart();
        expect(m.acting, isTrue);
        expect(await m.depart(), isFalse);
        c.complete(_load('on_route'));
        expect(await first, isTrue);
        verify(ops.departTruckLoad('l1')).called(1);
      });

      test('un 409 muestra el motivo del back y relee la carga', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('loading'));
        when(ops.departTruckLoad('l1')).thenThrow(_http(409, _kEnRuta));
        final m = MyLoadViewModel();
        await m.load();
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('on_route'));
        expect(await m.depart(), isFalse);
        expect(m.actionError, _kEnRuta);
        expect(m.openLoad!.status, TruckLoadStatus.onRoute);
        verify(api.myTruckLoad()).called(2);
      });

      test('sin red: no asume éxito ni relee', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('loading'));
        when(ops.departTruckLoad('l1')).thenThrow(_offline());
        final m = MyLoadViewModel();
        await m.load();
        expect(await m.depart(), isFalse);
        expect(m.openLoad!.status, TruckLoadStatus.loading);
        expect(m.actionError, isNotNull);
        verify(api.myTruckLoad()).called(1);
      });

      test('con la carga ya en ruta no se pide la salida', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('on_route'));
        final m = MyLoadViewModel();
        await m.load();
        expect(await m.depart(), isFalse);
        verifyNever(ops.departTruckLoad(any));
      });
    });

    group('Mi carga: regreso del camión', () {
      test('parte de lo esperado y manda todas las garrafas', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('on_route'));
        when(ops.returnTruckLoad('l1', any))
            .thenAnswer((_) async => _load('returned'));
        final m = MyLoadViewModel();
        await m.load();
        m.startReturn();
        final f = m.returnFields.single;
        expect(f.full.text, '10');
        expect(f.empty.text, '38');
        f.full.text = '9';
        expect(await m.submitReturn(), isTrue);
        final sent = verify(ops.returnTruckLoad('l1', captureAny))
            .captured
            .single as List<ReturnDeclaration>;
        expect(sent.single.toJson(),
            {'gasCylinderId': 'g1', 'declaredFull': 9, 'declaredEmpty': 38});
        expect(m.openLoad!.status, TruckLoadStatus.returned);
        m.dispose();
      });

      test('cantidades inválidas no llegan al back', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('on_route'));
        final m = MyLoadViewModel();
        await m.load();
        m.startReturn();
        m.returnFields.single.full.text = '';
        m.returnFields.single.empty.text = '4001';
        expect(await m.submitReturn(), isFalse);
        expect(m.returnFields.single.fullError, 'Ingresá una cantidad.');
        expect(m.returnFields.single.emptyError, 'No puede pasar de 4000.');
        verifyNever(ops.returnTruckLoad(any, any));
        m.dispose();
      });

      test('el 409 por pedidos en curso se muestra en el formulario', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('on_route'));
        when(ops.returnTruckLoad('l1', any))
            .thenThrow(_http(409, _kPedidosEnCurso));
        final m = MyLoadViewModel();
        await m.load();
        m.startReturn();
        expect(await m.submitReturn(), isFalse);
        expect(m.returnError, _kPedidosEnCurso);
        expect(m.openLoad!.status, TruckLoadStatus.onRoute);
        m.dispose();
      });

      test('doble toque: una sola declaración', () async {
        when(api.myTruckLoad()).thenAnswer((_) async => _mine('on_route'));
        final c = Completer<TruckLoad>();
        when(ops.returnTruckLoad('l1', any)).thenAnswer((_) => c.future);
        final m = MyLoadViewModel();
        await m.load();
        m.startReturn();
        final first = m.submitReturn();
        expect(await m.submitReturn(), isFalse);
        c.complete(_load('returned'));
        expect(await first, isTrue);
        verify(ops.returnTruckLoad('l1', any)).called(1);
        m.dispose();
      });

      test('ya devuelta se puede corregir con lo que declaró', () async {
        final json = _loadJson('returned');
        json['items'] = [
          {
            ...(json['items'] as List).single as Map<String, dynamic>,
            'declaredReturnFull': 7,
            'declaredReturnEmpty': 30,
          }
        ];
        when(api.myTruckLoad()).thenAnswer((_) async => MyTruckLoad(
            load: TruckLoad.fromJson(json), requireOpenTruckLoad: true));
        final m = MyLoadViewModel();
        await m.load();
        expect(m.openLoad!.canDeclareReturn, isTrue);
        m.startReturn();
        expect(m.returnFields.single.full.text, '7');
        expect(m.returnFields.single.empty.text, '30');
        m.dispose();
      });
    });

    group('Entrega en curso: liberar el pedido', () {
      var homeCalls = 0;

      DeliveryViewModel delivery() => DeliveryViewModel(
          orderId: 'o1',
          trips: trips,
          pollInterval: const Duration(hours: 1),
          goHome: () => homeCalls++);

      setUp(() {
        homeCalls = 0;
        when(trips.order('o1')).thenAnswer((_) async => trip());
        when(trips.customerRating(any)).thenAnswer((_) async => null);
      });

      test('con éxito corta el reparto y vuelve al Inicio', () async {
        when(trips.release('o1')).thenAnswer((_) async {});
        final m = delivery();
        await m.initialize();
        expect(m.canRelease, isTrue);
        expect(await m.releaseOrder(), isTrue);
        verify(trips.release('o1')).called(1);
        verify(socket.stopTracking()).called(1);
        verify(trips.endFlow()).called(1);
        expect(homeCalls, 1);
        expect(m.canRelease, isFalse);
        // No se suma el aviso de "Pedido liberado" del sondeo: lo hizo él.
        verifyNever(dialogs.showDialog(
            title: anyNamed('title'), description: anyNamed('description')));
        m.dispose();
      });

      test('doble toque: una sola llamada', () async {
        final c = Completer<void>();
        when(trips.release('o1')).thenAnswer((_) => c.future);
        final m = delivery();
        await m.initialize();
        final first = m.releaseOrder();
        expect(m.isReleasing, isTrue);
        expect(await m.releaseOrder(), isFalse);
        c.complete();
        expect(await first, isTrue);
        verify(trips.release('o1')).called(1);
        expect(homeCalls, 1);
        m.dispose();
      });

      test('un rechazo se muestra y el chofer sigue en la entrega', () async {
        when(trips.release('o1')).thenThrow(_http(400, _kFinalizado));
        final m = delivery();
        await m.initialize();
        expect(await m.releaseOrder(), isFalse);
        expect(m.errorMessage, _kFinalizado);
        expect(m.isReleasing, isFalse);
        expect(homeCalls, 0);
        verifyNever(trips.endFlow());
        m.dispose();
      });

      test('403 (ya no es suyo): relee y sale como pedido liberado', () async {
        when(trips.release('o1')).thenThrow(_http(403, _kNoAsignado));
        final m = delivery();
        await m.initialize();
        when(trips.order('o1')).thenThrow(_http(410, _kNoAsignado));
        expect(await m.releaseOrder(), isFalse);
        verify(dialogs.showDialog(
                title: 'Pedido liberado', description: anyNamed('description')))
            .called(1);
        expect(homeCalls, 1);
        m.dispose();
      });

      test('entregado no se puede liberar', () async {
        when(trips.order('o1'))
            .thenAnswer((_) async => trip(status: 'delivered'));
        final m = delivery();
        await m.initialize();
        expect(m.canRelease, isFalse);
        expect(await m.releaseOrder(), isFalse);
        verifyNever(trips.release(any));
        m.dispose();
      });
    });

    group('Detalle de la entrega', () {
      final order = DriverOrder(
          id: 'o1',
          status: DriverOrderStatus.delivered,
          total: 100,
          createdAt: DateTime(2026, 10, 3));

      test('lee incidencias e historial; si una falla la otra se ve', () async {
        when(api.orderIncidents('o1'))
            .thenThrow(_http(404, 'Pedido no encontrado'));
        when(api.orderStatusHistory('o1')).thenAnswer((_) async => const [
              StatusChange(toStatus: DriverOrderStatus.pending, isNote: false),
            ]);
        final m = DeliveryDetailViewModel(order);
        await m.load();
        expect(m.incidents.error, 'No encontramos lo que buscabas.');
        expect(m.history.items, hasLength(1));
        expect(m.history.error, isNull);

        when(api.orderIncidents('o1')).thenAnswer((_) async => const []);
        await m.loadIncidents();
        expect(m.incidents.error, isNull);
        expect(m.incidents.isEmpty, isTrue);
      });

      test('el 410 del historial sale con el texto propio', () async {
        when(api.orderIncidents('o1')).thenAnswer((_) async => const []);
        when(api.orderStatusHistory('o1')).thenThrow(_http(410, 'x'));
        final m = DeliveryDetailViewModel(order);
        await m.load();
        expect(m.history.error, 'El pedido ya no está asignado a vos.');
      });
    });
  });

  group('Pantallas', () {
    late MockDriverApiService api;
    late MockDriverOpsRepository ops;
    late MockTripService trips;

    setUp(() {
      registerServices();
      api = locator<DriverApiService>() as MockDriverApiService;
      ops = locator<DriverOpsRepository>() as MockDriverOpsRepository;
      trips = locator<TripService>() as MockTripService;
      final auth = locator<DriverAuthService>() as MockDriverAuthService;
      when(auth.userId).thenReturn('u1');
    });
    tearDown(() {
      DeliveryView.debugMapBuilder = null;
      DeliveryView.debugViewModelFactory = null;
      locator.reset();
    });

    Future<void> pump(WidgetTester t, Widget home) async {
      t.view.physicalSize = const Size(800, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: home));
      await t.pumpAndSettle();
    }

    testWidgets(
        'Mi carga en carga: «¿Confirmar la salida?»; cancelar no llama, '
        'confirmar sí', (t) async {
      when(api.myTruckLoad()).thenAnswer((_) async => _mine('loading'));
      when(ops.departTruckLoad('l1'))
          .thenAnswer((_) async => _load('on_route'));
      await pump(t, const MyLoadView());
      expect(find.byKey(const Key('my-load-return')), findsNothing);
      await t.tap(find.byKey(const Key('my-load-depart')));
      await t.pumpAndSettle();
      expect(find.text('¿Confirmar la salida?'), findsOneWidget);
      await t.tap(find.byKey(const Key('my-load-depart-cancel')));
      await t.pumpAndSettle();
      verifyNever(ops.departTruckLoad(any));

      await t.tap(find.byKey(const Key('my-load-depart')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('my-load-depart-confirm')));
      await t.pumpAndSettle();
      verify(ops.departTruckLoad('l1')).called(1);
      expect(find.text('En ruta'), findsOneWidget);
      expect(find.byKey(const Key('my-load-depart')), findsNothing);
      expect(find.byKey(const Key('my-load-return')), findsOneWidget);
    });

    testWidgets('Mi carga: el rechazo de la salida se ve en pantalla',
        (t) async {
      when(api.myTruckLoad()).thenAnswer((_) async => _mine('loading'));
      when(ops.departTruckLoad('l1')).thenThrow(
          _http(400, 'No alcanza el stock del depósito para la Garrafa 25kg'));
      await pump(t, const MyLoadView());
      await t.tap(find.byKey(const Key('my-load-depart')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('my-load-depart-confirm')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('my-load-action-error')), findsOneWidget);
      expect(find.text('No alcanza el stock del depósito para la Garrafa 25kg'),
          findsOneWidget);
    });

    testWidgets('Mi carga en ruta: declarar el regreso desde la hoja',
        (t) async {
      when(api.myTruckLoad()).thenAnswer((_) async => _mine('on_route'));
      final returned = _loadJson('returned');
      returned['items'] = [
        {
          ...(returned['items'] as List).single as Map<String, dynamic>,
          'declaredReturnFull': 10,
          'declaredReturnEmpty': 38,
        }
      ];
      when(ops.returnTruckLoad('l1', any))
          .thenAnswer((_) async => TruckLoad.fromJson(returned));
      await pump(t, const MyLoadView());
      await t.tap(find.byKey(const Key('my-load-return')));
      await t.pumpAndSettle();
      expect(find.text('Regreso del camión'), findsOneWidget);
      expect(find.byKey(const Key('return-full-g1')), findsOneWidget);
      await t.tap(find.byKey(const Key('return-submit')));
      await t.pumpAndSettle();
      verify(ops.returnTruckLoad('l1', any)).called(1);
      expect(find.text('Regreso del camión'), findsNothing);
      expect(find.text('Devuelta'), findsOneWidget);
      expect(find.byKey(const Key('my-load-declared-full-Garrafa 25kg')),
          findsOneWidget);
      expect(find.text('Corregir el regreso'), findsOneWidget);
    });

    testWidgets('Mi carga en ruta: el 409 queda en la hoja abierta', (t) async {
      when(api.myTruckLoad()).thenAnswer((_) async => _mine('on_route'));
      when(ops.returnTruckLoad('l1', any))
          .thenThrow(_http(409, _kPedidosEnCurso));
      await pump(t, const MyLoadView());
      await t.tap(find.byKey(const Key('my-load-return')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('return-submit')));
      await t.pumpAndSettle();
      expect(find.text('Regreso del camión'), findsOneWidget);
      expect(find.text(_kPedidosEnCurso), findsOneWidget);
    });

    testWidgets('Entrega en curso: «Liberar pedido» pide confirmación',
        (t) async {
      var home = 0;
      when(trips.order('o1')).thenAnswer((_) async => trip());
      when(trips.customerRating(any)).thenAnswer((_) async => null);
      when(trips.release('o1')).thenAnswer((_) async {});
      DeliveryView.debugMapBuilder = (_, __) => const SizedBox.expand();
      DeliveryView.debugViewModelFactory = (id) => DeliveryViewModel(
          orderId: id,
          trips: trips,
          pollInterval: const Duration(hours: 1),
          goHome: () => home++);
      await pump(t, const DeliveryView(orderId: 'o1'));
      await t.tap(find.byKey(const Key('trip-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trip-release')));
      await t.pumpAndSettle();
      expect(find.text('¿Liberar el pedido?'), findsOneWidget);
      await t.tap(find.byKey(const Key('trip-release-cancel')));
      await t.pumpAndSettle();
      verifyNever(trips.release(any));

      await t.tap(find.byKey(const Key('trip-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trip-release')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trip-release-confirm')));
      await t.pumpAndSettle();
      verify(trips.release('o1')).called(1);
      expect(home, 1);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Detalle: incidencias con su resolución e historial',
        (t) async {
      when(api.orderIncidents('o1')).thenAnswer((_) async => [
            const OrderIncident(
                id: 'i1',
                type: 'damaged',
                description: 'Válvula floja',
                status: IncidentStatus.resolved,
                resolutionNote: 'Se cambió la garrafa'),
          ]);
      when(api.orderStatusHistory('o1')).thenAnswer((_) async => const [
            StatusChange(toStatus: DriverOrderStatus.pending, isNote: false),
            StatusChange(
                fromStatus: DriverOrderStatus.pending,
                toStatus: DriverOrderStatus.accepted,
                isNote: false,
                actorRole: 'delivery'),
          ]);
      await pump(
          t,
          DeliveryDetailView(
              order: DriverOrder(
                  id: 'o1',
                  status: DriverOrderStatus.delivered,
                  total: 100,
                  createdAt: DateTime(2026, 10, 3))));
      expect(find.text('Garrafa dañada'), findsOneWidget);
      expect(find.text('Resuelta'), findsOneWidget);
      expect(find.text('Resolución: Se cambió la garrafa'), findsOneWidget);
      expect(find.text('Pendiente → Aceptado'), findsOneWidget);
      expect(find.byKey(const Key('detail-history-1')), findsOneWidget);
    });

    testWidgets('Detalle: error con reintento y vacío', (t) async {
      when(api.orderIncidents('o1')).thenThrow(_offline());
      when(api.orderStatusHistory('o1')).thenAnswer((_) async => const []);
      await pump(
          t,
          DeliveryDetailView(
              order: DriverOrder(
                  id: 'o1',
                  status: DriverOrderStatus.delivered,
                  total: 100,
                  createdAt: DateTime(2026, 10, 3))));
      expect(find.byKey(const Key('detail-incidents-error')), findsOneWidget);
      expect(find.byKey(const Key('detail-history-empty')), findsOneWidget);
      when(api.orderIncidents('o1')).thenAnswer((_) async => const []);
      await t.tap(find.byKey(const Key('detail-incidents-retry')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('detail-incidents-empty')), findsOneWidget);
    });
  });
}
