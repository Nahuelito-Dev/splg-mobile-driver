import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/services/payment_repository.dart';
import 'package:splg_driver/services/photo_picker.dart';
import 'package:splg_driver/ui/views/completed/completed_viewmodel.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/payment/payment_view.dart';
import 'package:splg_driver/ui/views/payment/payment_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

DioException http(int code, String msg) => DioException(
    requestOptions: RequestOptions(path: ''),
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: code,
        data: {'message': msg}));

void main() {
  late MockTripService trips;
  late MockPaymentRepository payments;
  late MockNavigationService nav;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    payments = locator<PaymentRepository>() as MockPaymentRepository;
    nav = locator<NavigationService>() as MockNavigationService;
    when(payments.confirmReceived('o1')).thenAnswer((_) async => true);
    when(payments.reportUnpaid('o1', note: anyNamed('note')))
        .thenAnswer((_) async => 'inc-1');
    when(trips.order('o1')).thenAnswer((_) async => trip(status: 'delivered'));
  });
  tearDown(() => locator.reset());

  PaymentViewModel vm() =>
      PaymentViewModel(orderId: 'o1', trips: trips, payments: payments);

  group('Pago recibido (efectivo pendiente)', () {
    test('llama al endpoint y recién ahí pasa a Completado', () async {
      final m = vm();
      await m.load();
      expect(m.needsCashConfirmation, true);
      await m.confirm();
      verifyInOrder([
        payments.confirmReceived('o1'),
        nav.replaceWithCompletedView(orderId: 'o1', paid: true),
      ]);
    });

    test('si falla muestra el motivo, NO avanza y deja reintentar', () async {
      final m = vm();
      await m.load();
      when(payments.confirmReceived('o1'))
          .thenThrow(http(400, 'El pedido todavía no fue entregado'));
      await m.confirm();
      expect(m.actionError, 'El pedido todavía no fue entregado');
      expect(m.submitting, false);
      verifyNever(nav.replaceWithCompletedView(orderId: 'o1', paid: true));
      // Reintento.
      when(payments.confirmReceived('o1')).thenAnswer((_) async => true);
      await m.confirm();
      expect(m.actionError, isNull);
      verify(nav.replaceWithCompletedView(orderId: 'o1', paid: true)).called(1);
    });

    test('sin red: texto de conexión y reintento', () async {
      final m = vm();
      await m.load();
      when(payments.confirmReceived('o1'))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '')));
      await m.confirm();
      expect(m.actionError, 'Sin conexión. Revisá tu internet.');
    });

    test('un segundo toque mientras confirma no duplica', () async {
      final m = vm();
      await m.load();
      final a = m.confirm();
      final b = m.confirm();
      await Future.wait([a, b]);
      verify(payments.confirmReceived('o1')).called(1);
    });
  });

  group('El cliente no pagó', () {
    test('manda la nota y pasa a Completado con el aviso', () async {
      final m = vm();
      await m.load();
      await m.reportUnpaid(note: 'Dijo que pagaba mañana');
      verify(payments.reportUnpaid('o1', note: 'Dijo que pagaba mañana'))
          .called(1);
      verify(nav.replaceWithCompletedView(orderId: 'o1', unpaid: true))
          .called(1);
    });

    test('sin nota también vale', () async {
      final m = vm();
      await m.load();
      await m.reportUnpaid();
      verify(payments.reportUnpaid('o1', note: null)).called(1);
    });

    test('si falla, muestra el error y no avanza', () async {
      final m = vm();
      await m.load();
      when(payments.reportUnpaid('o1', note: anyNamed('note')))
          .thenThrow(http(403, 'No tenés permiso'));
      await m.reportUnpaid(note: 'x');
      expect(m.actionError, isNotNull);
      verifyNever(nav.replaceWithCompletedView(
          orderId: 'o1', unpaid: true, photoFailed: false));
    });

    test('no aplica a Mercado Pago ni a un pago ya registrado', () async {
      when(trips.order('o1')).thenAnswer((_) async =>
          trip(status: 'delivered', method: 'online', paymentStatus: 'paid'));
      final online = vm();
      await online.load();
      expect(online.needsCashConfirmation, false);
      await online.reportUnpaid(note: 'x');
      verifyNever(payments.reportUnpaid(any, note: anyNamed('note')));

      when(trips.order('o1')).thenAnswer((_) async =>
          trip(status: 'delivered', method: 'cash', paymentStatus: 'paid'));
      final cashPaid = vm();
      await cashPaid.load();
      expect(cashPaid.needsCashConfirmation, false);
      expect(cashPaid.confirmLabel, 'Continuar');
      await cashPaid.confirm();
      verifyNever(payments.confirmReceived(any));
      verify(nav.replaceWithCompletedView(orderId: 'o1')).called(1);
    });
  });

  group('HttpPaymentRepository (contrato de cobro)', () {
    late MockApiClient api;
    late MockDriverAuthService auth;
    setUp(() {
      api = MockApiClient();
      auth = MockDriverAuthService();
      when(auth.token).thenAnswer((_) async => 'tok');
    });

    Response res(dynamic data) => Response(
        requestOptions: RequestOptions(path: ''), data: data, statusCode: 200);
    HttpPaymentRepository on() =>
        HttpPaymentRepository(api: api, auth: auth, enabled: true);

    test('sin habilitar (por defecto) no llama al back', () async {
      final repo = HttpPaymentRepository(api: api, auth: auth, enabled: false);
      expect(await repo.confirmReceived('o1'), true);
      expect(await repo.reportUnpaid('o1', note: 'x'), isNull);
      await repo.uploadIncidentPhoto('i', Uint8List(1));
      verifyNever(api.patch(any, any, any, any));
      verifyNever(api.putFile(any,
          bytes: anyNamed('bytes'),
          filename: anyNamed('filename'),
          contentType: anyNamed('contentType'),
          token: anyNamed('token')));
    });

    test('cash-received: PATCH sin cuerpo; true sólo si vuelve paid', () async {
      when(api.patch(any, any, any, any))
          .thenAnswer((_) async => res({'paymentStatus': 'paid'}));
      expect(await on().confirmReceived('o1'), true);
      verify(api.patch('orders/o1/payment/cash-received', {}, 'tok', any))
          .called(1);
      when(api.patch(any, any, any, any))
          .thenAnswer((_) async => res({'paymentStatus': 'pending'}));
      expect(await on().confirmReceived('o1'), false);
    });

    test(
        'unpaid: PATCH con la nota recortada y devuelve el id de la incidencia',
        () async {
      when(api.patch(any, any, any, any)).thenAnswer((_) async => res({
            'orderId': 'o1',
            'paymentStatus': 'unpaid',
            'incident': {'incident_id': 'inc-9', 'type': 'unpaid_collection'}
          }));
      final id = await on().reportUnpaid('o1', note: '  no estaba  ');
      expect(id, 'inc-9');
      verify(api.patch(
              'orders/o1/payment/unpaid', {'note': 'no estaba'}, 'tok', any))
          .called(1);
      await on().reportUnpaid('o1', note: 'x' * 800);
      verify(api.patch(
              'orders/o1/payment/unpaid', {'note': 'x' * 500}, 'tok', any))
          .called(1);
      await on().reportUnpaid('o1');
      verify(api.patch('orders/o1/payment/unpaid', {}, 'tok', any)).called(1);
    });

    test('Idempotency-Key: se reusa sin red y se descarta con respuesta',
        () async {
      final keys = <String>[];
      var n = 0;
      when(api.patch(any, any, any, any)).thenAnswer((i) async {
        keys.add((i.positionalArguments[3]
            as Map<String, String>)['Idempotency-Key']!);
        n++;
        if (n == 1)
          throw DioException(requestOptions: RequestOptions(path: ''));
        if (n == 2) throw http(409, 'El pago ya estaba cobrado');
        return res({'paymentStatus': 'paid'});
      });
      final repo = on();
      await expectLater(
          repo.confirmReceived('o1'), throwsA(isA<DioException>()));
      await expectLater(
          repo.confirmReceived('o1'), throwsA(isA<DioException>()));
      expect(keys[0], keys[1], reason: 'sin respuesta: misma clave');
      await repo.confirmReceived('o1');
      expect(keys[2], isNot(keys[1]), reason: 'tras un rechazo: clave nueva');
    });

    test('la foto va por PUT multipart a la incidencia', () async {
      when(api.putFile(any,
              bytes: anyNamed('bytes'),
              filename: anyNamed('filename'),
              contentType: anyNamed('contentType'),
              token: anyNamed('token')))
          .thenAnswer((_) async => res({}));
      await on().uploadIncidentPhoto('inc-9', Uint8List.fromList([1, 2]));
      verify(api.putFile('incidents/inc-9/photo',
              bytes: [1, 2],
              filename: 'incidencia.jpg',
              contentType: 'image/jpeg',
              token: 'tok'))
          .called(1);
    });
  });

  group('Completado: "¡Ganaste!" sólo con lo cobrado', () {
    CompletedViewModel done({bool paid = false}) => CompletedViewModel(
        orderId: 'o1', trips: trips, goHome: () {}, paid: paid);

    test('cobro confirmado por el back: cuenta el total', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      final m = done(paid: true);
      await m.load();
      m.finish();
      verify(trips.endFlow(earned: 28310)).called(1);
    });

    test('Mercado Pago ya pagado: cuenta el total', () async {
      when(trips.order('o1')).thenAnswer((_) async =>
          trip(status: 'delivered', method: 'online', paymentStatus: 'paid'));
      final m = done();
      await m.load();
      m.finish();
      verify(trips.endFlow(earned: 28310)).called(1);
    });

    test('impago o pendiente: no suma nada', () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      final m = done();
      await m.load();
      m.finish();
      verify(trips.endFlow(earned: null)).called(1);
    });
  });

  group('pantalla de Cobro', () {
    Future<void> pump(WidgetTester t) async {
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      PaymentView.debugViewModelFactory = (id) => vm();
      addTearDown(() => PaymentView.debugViewModelFactory = null);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme, home: const PaymentView(orderId: 'o1')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('efectivo pendiente: "Pago recibido" y "El cliente no pagó"',
        (t) async {
      await pump(t);
      expect(find.text('Pago recibido'), findsOneWidget);
      expect(find.text('El cliente no pagó'), findsOneWidget);
    });

    testWidgets('el reporte pide confirmación y deja escribir una nota',
        (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('payment-unpaid')));
      await t.pumpAndSettle();
      expect(find.text('¿El cliente no pagó?'), findsOneWidget);
      verifyNever(payments.reportUnpaid(any, note: anyNamed('note')));
      await t.enterText(find.byType(TextField), 'No estaba en casa');
      await t.tap(find.byKey(const Key('unpaid-confirm')));
      await t.pumpAndSettle();
      verify(payments.reportUnpaid('o1', note: 'No estaba en casa')).called(1);
    });

    testWidgets('adjuntar una foto y confirmar la manda con el reporte',
        (t) async {
      final jpeg = Uint8List.fromList(_tinyPng);
      PaymentView.debugPhotoPicker = _FakePicker(jpeg);
      addTearDown(() => PaymentView.debugPhotoPicker = null);
      await pump(t);
      await t.tap(find.byKey(const Key('payment-unpaid')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('unpaid-camera')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('unpaid-photo')), findsOneWidget);
      await t.tap(find.byKey(const Key('unpaid-photo-remove')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('unpaid-photo')), findsNothing);
      await t.tap(find.byKey(const Key('unpaid-gallery')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('unpaid-confirm')));
      await t.pumpAndSettle();
      verify(payments.uploadIncidentPhoto('inc-1', jpeg)).called(1);
    });

    testWidgets('si la foto falla se avisa y se puede seguir sin ella',
        (t) async {
      PaymentView.debugPhotoPicker = _FakePicker(null, fail: true);
      addTearDown(() => PaymentView.debugPhotoPicker = null);
      await pump(t);
      await t.tap(find.byKey(const Key('payment-unpaid')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('unpaid-camera')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('unpaid-photo-error')), findsOneWidget);
      await t.tap(find.byKey(const Key('unpaid-confirm')));
      await t.pumpAndSettle();
      verify(payments.reportUnpaid('o1', note: '')).called(1);
      verifyNever(payments.uploadIncidentPhoto(any, any));
    });

    testWidgets('cancelar la hoja no reporta nada', (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('payment-unpaid')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('unpaid-cancel')));
      await t.pumpAndSettle();
      verifyNever(payments.reportUnpaid(any, note: anyNamed('note')));
    });

    testWidgets('error al confirmar: se ve el mensaje y el botón sigue',
        (t) async {
      when(payments.confirmReceived('o1'))
          .thenThrow(http(400, 'No se pudo registrar el pago'));
      await pump(t);
      await t.tap(find.byKey(const Key('payment-confirm')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('payment-action-error')), findsOneWidget);
      expect(find.text('Pago recibido'), findsOneWidget);
    });

    testWidgets('Mercado Pago pagado: sin los botones de efectivo', (t) async {
      when(trips.order('o1')).thenAnswer((_) async =>
          trip(status: 'delivered', method: 'online', paymentStatus: 'paid'));
      await pump(t);
      expect(find.text('El cliente no pagó'), findsNothing);
      expect(find.text('Pago recibido'), findsNothing);
      expect(find.text('Continuar'), findsOneWidget);
    });
  });
}

class _FakePicker implements PhotoPicker {
  _FakePicker(this.bytes, {this.fail = false});
  final Uint8List? bytes;
  final bool fail;
  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    if (fail) throw Exception('sin permiso');
    return bytes;
  }
}

/// PNG de 1x1 (para que `Image.memory` pueda decodificarlo).
const _tinyPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xFF,
  0xFF,
  0x3F,
  0x00,
  0x05,
  0xFE,
  0x02,
  0xFE,
  0xA7,
  0x35,
  0x81,
  0x84,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
