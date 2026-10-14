import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mockito/mockito.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/photo_picker.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/completed/completed_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_driver/ui/views/payment/payment_view.dart';
import 'package:splg_driver/ui/views/payment/payment_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import '../tanda3/support.dart';
import 'support.dart';

/// Pedido entregado en efectivo con la seña ya paga: total $31.900, seña
/// $9.570 y saldo $22.330 (forma de `GET /orders/:id`).
TripOrder conSena({bool depositPaid = true}) => TripOrder.fromJson({
      ...orderJson(status: 'delivered', total: 31900),
      'depositAmount': 9570,
      'depositPaid': depositPaid,
      'remainingBalance': depositPaid ? 22330 : 31900,
    });

DriverOrder driverOrder(String id,
        {DriverOrderStatus status = DriverOrderStatus.accepted,
        String method = 'cash',
        String paymentStatus = 'pending'}) =>
    DriverOrder(
      id: id,
      status: status,
      total: 1000,
      createdAt: DateTime.now(),
      deliveredAt: DateTime.now(),
      paymentMethod: method,
      paymentStatus: paymentStatus,
    );

void main() {
  late MockDriverApiService api;
  late MockNavigationService nav;
  late MockTripService trips;
  late MockDriverAuthService auth;
  late MockDriverSocketService socket;

  setUp(() {
    registerServices();
    api = locator<DriverApiService>() as MockDriverApiService;
    nav = locator<NavigationService>() as MockNavigationService;
    trips = locator<TripService>() as MockTripService;
    auth = locator<DriverAuthService>() as MockDriverAuthService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
  });
  tearDown(() => locator.reset());

  group('1. Seña: se cobra el saldo, no el total', () {
    test('el modelo lee seña y saldo del back', () {
      final o = conSena();
      expect(o.hasPaidDeposit, true);
      expect(o.amountToCollect, 22330);
      expect(o.total, 31900);
      expect(conSena(depositPaid: false).amountToCollect, 31900);
      expect(conSena(depositPaid: false).hasPaidDeposit, false);
    });

    test('sin los campos nuevos se cobra el total', () {
      final o = TripOrder.fromJson(orderJson(total: 5000));
      expect(o.amountToCollect, 5000);
      expect(o.hasPaidDeposit, false);
    });

    Future<void> pumpPayment(WidgetTester t, TripOrder order) async {
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      when(trips.order('o1')).thenAnswer((_) async => order);
      PaymentView.debugViewModelFactory =
          (id) => PaymentViewModel(orderId: id, trips: trips);
      addTearDown(() => PaymentView.debugViewModelFactory = null);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme, home: const PaymentView(orderId: 'o1')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('la pantalla de cobro muestra el saldo y aclara la seña',
        (t) async {
      await pumpPayment(t, conSena());
      expect(t.widget<Text>(find.byKey(const Key('payment-total'))).data,
          formatMoney(22330));
      final deposit = t.widget<Text>(find.byKey(const Key('payment-deposit')));
      expect(deposit.data, contains(formatMoney(31900)));
      expect(deposit.data, contains(formatMoney(9570)));
      expect(deposit.data, contains('seña ya paga'));
    });

    testWidgets('sin seña muestra el total y ninguna aclaración', (t) async {
      await pumpPayment(t, conSena(depositPaid: false));
      expect(t.widget<Text>(find.byKey(const Key('payment-total'))).data,
          formatMoney(31900));
      expect(find.byKey(const Key('payment-deposit')), findsNothing);
    });

    test('"¡Ganaste!" suma lo cobrado (el saldo), no el total', () async {
      when(trips.order('o1')).thenAnswer((_) async => conSena());
      final m = CompletedViewModel(
          orderId: 'o1', trips: trips, goHome: () {}, paid: true);
      await m.load();
      m.finish();
      verify(trips.endFlow(earned: 22330)).called(1);
    });
  });

  group('2 y 6. Retomar pedidos al abrir y al terminar un flujo', () {
    HomeViewModel home() =>
        HomeViewModel(trips: trips, isHomeVisible: () => true);

    void pages(List<List<DriverOrder>> responses) {
      var i = 0;
      when(api.activeOrder()).thenAnswer((_) async {
        final list = responses[i < responses.length ? i : responses.length - 1];
        i++;
        return list.isEmpty ? null : list.first;
      });
    }

    test('un pedido entregado con efectivo pendiente se retoma en el cobro',
        () async {
      pages([
        [driverOrder('o9', status: DriverOrderStatus.delivered)]
      ]);
      await home().resumeActiveOrder();
      verify(nav.navigateToPaymentView(orderId: 'o9')).called(1);
      verify(trips.beginFlow('o9')).called(greaterThan(0));
    });

    test('no retoma el cobro si ya está pagado, es impago u online', () async {
      for (final o in [
        driverOrder('a',
            status: DriverOrderStatus.delivered, paymentStatus: 'paid'),
        driverOrder('b',
            status: DriverOrderStatus.delivered, paymentStatus: 'unpaid'),
        driverOrder('c', status: DriverOrderStatus.delivered, method: 'online'),
      ]) {
        pages([
          [o]
        ]);
        await home().resumeActiveOrder();
      }
      for (final id in ['a', 'b', 'c']) {
        verifyNever(nav.navigateToPaymentView(orderId: id));
      }
    });

    test('un pedido en curso gana al cobro pendiente', () async {
      pages([
        [driverOrder('curso')]
      ]);
      await home().resumeActiveOrder();
      verify(nav.navigateToDeliveryView(orderId: 'curso')).called(1);
      verifyNever(nav.navigateToPaymentView(orderId: 'cobro'));
    });

    test('al terminar un pedido aparece el que el admin asignó mientras tanto',
        () async {
      pages([
        [driverOrder('o1')],
        [driverOrder('o2')],
      ]);
      await home().resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyInOrder([
        nav.navigateToDeliveryView(orderId: 'o1'),
        nav.navigateToDeliveryView(orderId: 'o2'),
      ]);
    });

    test('no reabre en bucle el pedido que acaba de terminar su flujo',
        () async {
      pages([
        [driverOrder('o1')]
      ]);
      await home().resumeActiveOrder();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(nav.navigateToDeliveryView(orderId: 'o1')).called(1);
    });
  });

  group('7. Socket: token vencido y respaldo', () {
    test('aplica el token nuevo al auth y al header del handshake', () async {
      var token = 'viejo';
      final svc = DriverSocketService(tokenProvider: () async => token);
      final s = io.io(
          'http://localhost:1',
          io.OptionBuilder()
              .setTransports(['websocket'])
              .setAuth({'token': 'viejo'})
              .disableAutoConnect()
              .build());
      token = 'nuevo';
      await svc.applyFreshToken(s);
      expect(s.auth, {'token': 'nuevo'});
      expect(s.io.options?['extraHeaders'], {'Authorization': 'Bearer nuevo'});
      s.dispose();
    });

    test('un error de conexión pide un token nuevo', () async {
      final asked = Completer<void>();
      late io.Socket created;
      final svc = DriverSocketService(
        tokenProvider: () async {
          if (!asked.isCompleted) asked.complete();
          return 'nuevo';
        },
        socketFactory: (uri, opts) => created = io.io('http://localhost:1',
            {...opts, 'autoConnect': false, 'forceNew': true}),
      );
      svc.connect('vencido', 'd1');
      created.onerror('token vencido');
      await asked.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(created.auth, {'token': 'nuevo'});
      svc.disconnect();
    });

    test('si el servidor lo desconecta (token vencido) también renueva',
        () async {
      var calls = 0;
      late io.Socket created;
      final svc = DriverSocketService(
        tokenProvider: () async {
          calls++;
          return 'nuevo';
        },
        socketFactory: (uri, opts) => created = io.io('http://localhost:1',
            {...opts, 'autoConnect': false, 'forceNew': true}),
      );
      svc.connect('vencido', 'd1');
      // Deja pasar el rechazo del primer intento contra el puerto cerrado.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final before = calls;
      created.onclose('io server disconnect');
      // Reintenta con espera creciente (la primera, de medio segundo a uno).
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(calls, greaterThan(before));
      svc.disconnect();
    });

    group('sondeo de respaldo del Inicio', () {
      const every = Duration(seconds: 20);

      Future<HomeViewModel> started(WidgetTester t) async {
        when(api.noOrdersReason()).thenAnswer((_) async => null);
        final m =
            HomeViewModel(loadPollInterval: every, isHomeVisible: () => true);
        m.initialise();
        unawaited(m.initialize());
        await t.pump();
        clearInteractions(socket);
        return m;
      }

      testWidgets('en línea y sin socket: renueva credenciales y busca pedidos',
          (t) async {
        when(socket.hasSocket).thenReturn(true);
        when(socket.isConnected).thenReturn(false);
        final m = await started(t);
        await t.pump(every);
        verify(socket.ensureConnected()).called(1);
        m.dispose();
      });

      testWidgets('con el socket conectado no hace nada', (t) async {
        when(socket.hasSocket).thenReturn(true);
        when(socket.isConnected).thenReturn(true);
        final m = await started(t);
        await t.pump(every);
        verifyNever(socket.ensureConnected());
        m.dispose();
      });

      testWidgets('fuera de línea no reconecta', (t) async {
        when(socket.hasSocket).thenReturn(false);
        when(socket.isConnected).thenReturn(false);
        final m = await started(t);
        await t.pump(every);
        verifyNever(socket.ensureConnected());
        m.dispose();
      });
    });
  });

  group('3. Fotos', () {
    Uint8List jpegConExif({int width = 40, int height = 20}) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(200, 30, 30));
      image.exif.imageIfd.orientation = 6; // girada 90 grados
      image.exif.imageIfd.make = 'MARCA-SECRETA';
      return Uint8List.fromList(img.encodeJpg(image));
    }

    test('hornea la orientación EXIF: la foto no sale girada', () async {
      final out = await ImagePickerPhotoPicker.sanitize(jpegConExif());
      final decoded = img.decodeImage(out)!;
      expect([decoded.width, decoded.height], [20, 40]);
    });

    test('no deja metadatos', () async {
      final out = await ImagePickerPhotoPicker.sanitize(jpegConExif());
      expect(String.fromCharCodes(out).contains('MARCA-SECRETA'), false);
      expect(img.decodeImage(out)!.exif.isEmpty, true);
    });

    test('acepta PNG y lo deja en JPEG', () async {
      final png = img.encodePng(img.Image(width: 30, height: 30));
      final out =
          await ImagePickerPhotoPicker.sanitize(Uint8List.fromList(png));
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
    });

    test('reduce a 1280 px del lado mayor', () async {
      final big = jpegConExif(width: 3000, height: 1000);
      final out = await ImagePickerPhotoPicker.sanitize(big);
      final decoded = img.decodeImage(out)!;
      // Está girada por la orientación: 1000x3000 -> lado mayor 1280.
      expect(decoded.height, 1280);
    });

    test('lo que no se puede leer lanza en vez de subirse sin limpiar',
        () async {
      await expectLater(
          ImagePickerPhotoPicker.sanitize(Uint8List.fromList([1, 2, 3, 4])),
          throwsFormatException);
    });

    Future<File> temp(Uint8List bytes) async {
      final dir = await Directory.systemTemp.createTemp('foto_test');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/foto.jpg');
      await f.writeAsBytes(bytes);
      return f;
    }

    test('borra el temporal del selector tras leerlo', () async {
      final f = await temp(jpegConExif());
      final out = await ImagePickerPhotoPicker.fromFile(XFile(f.path));
      expect(out, isNotEmpty);
      expect(f.existsSync(), false);
    });

    test('borra el temporal aunque la foto no se pueda leer', () async {
      final f = await temp(Uint8List.fromList([9, 9, 9]));
      await expectLater(ImagePickerPhotoPicker.fromFile(XFile(f.path)),
          throwsFormatException);
      expect(f.existsSync(), false);
    });

    test('pick: devuelve la foto limpia y borra el temporal; cancelar da null',
        () async {
      final f = await temp(jpegConExif());
      final picker = ImagePickerPhotoPicker(picker: _FakeImagePicker(f.path));
      final out = await picker.pick(PhotoSource.gallery);
      expect(img.decodeImage(out!)!.width, 20);
      expect(f.existsSync(), false);
      final cancel = ImagePickerPhotoPicker(picker: _FakeImagePicker(null));
      expect(await cancel.pick(PhotoSource.camera), isNull);
    });
  });

  group('4. Log de red', () {
    test('en release no loguea nada', () {
      expect(ApiClient.buildLogger(debug: false).enabled, false);
    });

    test('nunca imprime los encabezados (el Bearer va ahí)', () {
      expect(ApiClient.buildLogger(debug: true).requestHeader, false);
      expect(ApiClient.buildLogger(debug: false).requestHeader, false);
    });
  });

  group('5. Sondeo del pedido en curso sin consultas apiladas', () {
    test('con una lectura en vuelo no se piden más', () async {
      when(trips.order('o1')).thenAnswer((_) async => trip());
      when(trips.customerRating('c1')).thenAnswer((_) async => null);
      final m = DeliveryViewModel(
        orderId: 'o1',
        trips: trips,
        pollInterval: const Duration(milliseconds: 20),
        goHome: () {},
      );
      await m.initialize();
      final slow = Completer<TripOrder>();
      clearInteractions(trips);
      when(trips.order('o1')).thenAnswer((_) => slow.future);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      verify(trips.order('o1')).called(1);
      slow.complete(trip());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(trips.order('o1')).called(greaterThan(0));
      m.dispose();
    });
  });

  group('10. Idempotencia de incidencias y envases', () {
    late MockApiClient client;
    late MockDriverAuthService svcAuth;
    late TripService svc;

    Response ok() => Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 201,
        data: <String, dynamic>{});
    DioException offline() =>
        DioException(requestOptions: RequestOptions(path: ''));
    String keyOf(Invocation i) =>
        (i.positionalArguments[3] as Map<String, String>)['Idempotency-Key']!;

    setUp(() {
      client = MockApiClient();
      svcAuth = MockDriverAuthService();
      when(svcAuth.token).thenAnswer((_) async => 'tok');
      svc = TripService(api: client, auth: svcAuth);
    });

    for (final c in [
      (
        'incidencia',
        'incidents',
        (TripService s) => s.reportIncident('o1', 'damaged', 'rota'),
      ),
      (
        'envases',
        'cylinders/assign',
        (TripService s) => s.assignCylinders('o1', ['A1']),
      ),
    ]) {
      test('${c.$1}: sin respuesta el reintento reusa la clave', () async {
        final keys = <String>[];
        var n = 0;
        when(client.post(c.$2, any, any, any)).thenAnswer((i) async {
          keys.add(keyOf(i));
          if (++n == 1) throw offline();
          return ok();
        });
        await expectLater(c.$3(svc), throwsA(isA<DioException>()));
        await c.$3(svc);
        expect(keys[0], keys[1]);
      });

      test('${c.$1}: tras un rechazo de negocio la clave se descarta',
          () async {
        final keys = <String>[];
        when(client.post(c.$2, any, any, any)).thenAnswer((i) async {
          keys.add(keyOf(i));
          if (keys.length == 1) {
            throw DioException(
                requestOptions: RequestOptions(path: ''),
                response: Response(
                    requestOptions: RequestOptions(path: ''),
                    statusCode: 400,
                    data: {'message': 'El pedido no está en camino'}));
          }
          return ok();
        });
        await expectLater(c.$3(svc), throwsA(isA<DioException>()));
        await c.$3(svc);
        expect(keys[0], isNot(keys[1]));
      });

      test('${c.$1}: tras una respuesta la clave se descarta', () async {
        final keys = <String>[];
        when(client.post(c.$2, any, any, any)).thenAnswer((i) async {
          keys.add(keyOf(i));
          return ok();
        });
        await c.$3(svc);
        await c.$3(svc);
        expect(keys[0], isNot(keys[1]));
      });
    }

    test('el 422 de idempotencia de una incidencia se explica y refresca',
        () async {
      when(trips.order('o1')).thenAnswer((_) async => trip());
      when(trips.customerRating('c1')).thenAnswer((_) async => null);
      when(trips.reportIncident('o1', 'damaged', 'otra'))
          .thenThrow(idempotency422());
      final m = DeliveryViewModel(orderId: 'o1', trips: trips, goHome: () {});
      await m.initialize();
      clearInteractions(trips);
      final ok = await m.reportIncident(type: 'damaged', description: 'otra');
      expect(ok, false);
      expect(m.errorMessage, kIdempotencyConflictText);
      verify(trips.order('o1')).called(1);
      m.dispose();
    });

    test('el 422 al despachar envases se explica', () async {
      when(trips.order('o1')).thenAnswer((_) async => trip());
      when(trips.customerRating('c1')).thenAnswer((_) async => null);
      when(trips.assignCylinders('o1', ['A1'])).thenThrow(idempotency422());
      final m = DeliveryViewModel(orderId: 'o1', trips: trips, goHome: () {});
      await m.initialize();
      expect(await m.assignCylinders(['A1']), false);
      expect(m.cylinderError, kIdempotencyConflictText);
      m.dispose();
    });
  });

  group('8 y 9. Higiene del código', () {
    List<File> dartFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('no hay íconos de Material (se usa Phosphor)', () {
      final offenders = [
        for (final f in dartFiles())
          if (RegExp(r'(?<![A-Za-z])Icons\.').hasMatch(f.readAsStringSync()))
            f.path
      ];
      expect(offenders, isEmpty);
    });

    test('no hay print() en el código de producción', () {
      final offenders = [
        for (final f in dartFiles())
          if (RegExp(r'(?<![A-Za-z_.])print\(').hasMatch(f.readAsStringSync()))
            f.path
      ];
      expect(offenders, isEmpty);
    });

    test('el OrderService con pedidos de mentira ya no existe', () {
      expect(File('lib/services/order_service.dart').existsSync(), false);
    });
  });
}

class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.path);

  final String? path;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      path == null ? null : XFile(path!);
}
