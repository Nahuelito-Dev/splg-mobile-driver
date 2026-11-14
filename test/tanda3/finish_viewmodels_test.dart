import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/completed/completed_viewmodel.dart';
import 'package:splg_driver/ui/views/delivery_qr/delivery_qr_viewmodel.dart';
import 'package:splg_driver/ui/views/payment/payment_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'support.dart';

DioException http(int code, [dynamic data]) => DioException(
    requestOptions: RequestOptions(path: ''),
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: code,
        data: data));

void main() {
  late MockTripService trips;
  late MockNavigationService nav;
  late MockDialogService dialogs;
  late MockDriverSocketService socket;
  var homeCalls = 0;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    dialogs = locator<DialogService>() as MockDialogService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    homeCalls = 0;
    when(trips.order('o1'))
        .thenAnswer((_) async => trip(status: 'out_for_delivery'));
    when(trips.deliveryCode('o1'))
        .thenAnswer((_) async => const DeliveryCodeInfo('A1B2C3D4E5'));
    when(trips.customerRating(any)).thenAnswer((_) async => null);
  });
  tearDown(() => locator.reset());

  group('QR de entrega', () {
    DeliveryQrViewModel qr() => DeliveryQrViewModel(
        orderId: 'o1',
        trips: trips,
        pollInterval: const Duration(milliseconds: 20),
        goHome: () => homeCalls++);

    test('muestra el código del back y espera la confirmación', () async {
      final m = qr();
      await m.initialize();
      expect(m.code, 'A1B2C3D4E5');
      expect(m.loadError, isNull);
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      m.dispose();
    });

    group('aviso de código bloqueado', () {
      late StreamController<Map<String, dynamic>> codeEvents;

      setUp(() {
        codeEvents = StreamController<Map<String, dynamic>>.broadcast();
        when(socket.deliveryCodeFailed).thenAnswer((_) => codeEvents.stream);
      });
      tearDown(() => codeEvents.close());

      Map<String, dynamic> ev(int n,
              {bool blocked = false, String id = 'o1'}) =>
          {'orderId': id, 'attempts': n, 'maxAttempts': 5, 'blocked': blocked};

      test('al abrir ya bloqueado, lo informa el GET', () async {
        when(trips.deliveryCode('o1')).thenAnswer((_) async =>
            const DeliveryCodeInfo('A1B2C3D4E5', attempts: 5, blocked: true));
        final m = qr();
        await m.initialize();
        expect(m.blocked, isTrue);
        expect(m.attempts, 5);
        m.dispose();
      });

      test('el evento del socket bloquea la pantalla al instante', () async {
        final m = qr();
        await m.initialize();
        expect(m.blocked, isFalse);
        codeEvents.add(ev(5, blocked: true));
        await Future<void>.delayed(Duration.zero);
        expect(m.blocked, isTrue);
        expect(m.attempts, 5);
        m.dispose();
      });

      test('del 3.er error avisa; antes no, y de otro pedido no cuenta',
          () async {
        final m = qr();
        await m.initialize();
        codeEvents.add(ev(2));
        await Future<void>.delayed(Duration.zero);
        expect(m.showAttemptsWarning, isFalse);
        codeEvents.add(ev(3));
        await Future<void>.delayed(Duration.zero);
        expect(m.showAttemptsWarning, isTrue);
        expect(m.blocked, isFalse);
        codeEvents.add(ev(5, blocked: true, id: 'otro'));
        await Future<void>.delayed(Duration.zero);
        expect(m.blocked, isFalse);
        m.dispose();
      });

      test('si el socket perdió el aviso, el sondeo lo recupera', () async {
        final m = qr();
        await m.initialize();
        when(trips.deliveryCode('o1')).thenAnswer((_) async =>
            const DeliveryCodeInfo('A1B2C3D4E5', attempts: 5, blocked: true));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(m.blocked, isTrue);
        m.dispose();
      });

      test('una lectura vieja del sondeo no pisa un aviso más nuevo', () async {
        final m = DeliveryQrViewModel(
            orderId: 'o1',
            trips: trips,
            pollInterval: const Duration(milliseconds: 20),
            goHome: () => homeCalls++);
        await m.initialize();
        final vieja = Completer<DeliveryCodeInfo>();
        when(trips.deliveryCode('o1')).thenAnswer((_) => vieja.future);
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // El aviso del socket llega mientras la lectura sigue en vuelo.
        when(trips.deliveryCode('o1')).thenAnswer((_) async =>
            const DeliveryCodeInfo('A1B2C3D4E5', attempts: 5, blocked: true));
        codeEvents.add(ev(5, blocked: true));
        await Future<void>.delayed(Duration.zero);
        vieja.complete(const DeliveryCodeInfo('A1B2C3D4E5'));
        await Future<void>.delayed(Duration.zero);

        expect(m.blocked, isTrue);
        expect(m.attempts, 5);
        m.dispose();
      });

      test('una lectura vieja no revive el bloqueo tras generar el código',
          () async {
        when(trips.deliveryCode('o1')).thenAnswer((_) async =>
            const DeliveryCodeInfo('A1B2C3D4E5', attempts: 5, blocked: true));
        when(trips.regenerateDeliveryCode('o1'))
            .thenAnswer((_) async => '482913');
        final m = DeliveryQrViewModel(
            orderId: 'o1',
            trips: trips,
            pollInterval: const Duration(milliseconds: 20),
            goHome: () => homeCalls++);
        await m.initialize();
        final vieja = Completer<DeliveryCodeInfo>();
        when(trips.deliveryCode('o1')).thenAnswer((_) => vieja.future);
        await Future<void>.delayed(const Duration(milliseconds: 60));

        await m.regenerateCode();
        when(trips.deliveryCode('o1'))
            .thenAnswer((_) async => const DeliveryCodeInfo('482913'));
        vieja.complete(
            const DeliveryCodeInfo('A1B2C3D4E5', attempts: 5, blocked: true));
        await Future<void>.delayed(Duration.zero);

        expect(m.blocked, isFalse);
        expect(m.code, '482913');
        m.dispose();
      });

      test('el número mostrado no pasa del tope (6.º simultáneo)', () async {
        final m = qr();
        await m.initialize();
        codeEvents.add(ev(6, blocked: true));
        await Future<void>.delayed(Duration.zero);
        expect(m.attempts, 5);
        m.dispose();
      });

      test('al bloquearse se cierra la confirmación pendiente', () async {
        final m = qr();
        await m.initialize();
        m.askRegenerate();
        expect(m.confirmingRegenerate, isTrue);
        codeEvents.add(ev(5, blocked: true));
        await Future<void>.delayed(Duration.zero);
        expect(m.confirmingRegenerate, isFalse);
        m.dispose();
      });

      test('la primera lectura vieja no pisa un aviso que llegó antes',
          () async {
        final lenta = Completer<DeliveryCodeInfo>();
        when(trips.deliveryCode('o1')).thenAnswer((_) => lenta.future);
        final m = qr();
        final init = m.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        codeEvents.add(ev(5, blocked: true));
        await Future<void>.delayed(Duration.zero);
        lenta.complete(const DeliveryCodeInfo('A1B2C3D4E5'));
        await init;
        expect(m.blocked, isTrue);
        expect(m.attempts, 5);
        expect(m.code, 'A1B2C3D4E5');
        m.dispose();
      });

      test('bloqueado, generar código nuevo va directo y limpia el aviso',
          () async {
        when(trips.regenerateDeliveryCode('o1'))
            .thenAnswer((_) async => '482913');
        final m = qr();
        await m.initialize();
        codeEvents.add(ev(5, blocked: true));
        await Future<void>.delayed(Duration.zero);

        m.askRegenerate();
        await Future<void>.delayed(Duration.zero);

        verify(trips.regenerateDeliveryCode('o1')).called(1);
        expect(m.confirmingRegenerate, isFalse);
        expect(m.blocked, isFalse);
        expect(m.attempts, 0);
        expect(m.code, '482913');
        m.dispose();
      });

      test('si el back no genera el código, sigue bloqueado con el motivo',
          () async {
        when(trips.regenerateDeliveryCode('o1'))
            .thenThrow(StateError('El pedido ya no está en camino'));
        final m = qr();
        await m.initialize();
        codeEvents.add(ev(5, blocked: true));
        await Future<void>.delayed(Duration.zero);

        await m.regenerateCode();

        expect(m.blocked, isTrue);
        expect(m.regenerateError, 'El pedido ya no está en camino');
        m.dispose();
      });
    });

    test('el código de 6 dígitos se lee agrupado y uno viejo queda como está',
        () {
      expect(DeliveryQrViewModel.formatCode('482913'), '482 913');
      expect(DeliveryQrViewModel.formatCode('A1B2C3D4E5'), 'A1B2C3D4E5');
    });

    test(
        'generar código nuevo pide confirmación y muestra el nuevo al instante',
        () async {
      when(trips.regenerateDeliveryCode('o1'))
          .thenAnswer((_) async => '482913');
      final m = qr();
      await m.initialize();

      m.askRegenerate();
      expect(m.confirmingRegenerate, isTrue);
      verifyNever(trips.regenerateDeliveryCode(any));

      await m.regenerateCode();

      expect(m.code, '482913');
      expect(m.displayCode, '482 913');
      expect(m.confirmingRegenerate, isFalse);
      expect(m.regenerateError, isNull);
      m.dispose();
    });

    test('si el back no lo genera, queda el código actual y el motivo',
        () async {
      when(trips.regenerateDeliveryCode('o1'))
          .thenThrow(StateError('El pedido ya no está en camino'));
      final m = qr();
      await m.initialize();
      m.askRegenerate();

      await m.regenerateCode();

      expect(m.code, 'A1B2C3D4E5');
      expect(m.regenerateError, 'El pedido ya no está en camino');
      expect(m.confirmingRegenerate, isTrue);
      m.dispose();
    });

    test(
        'el cliente escanea (delivered): corta tracking y va al cobro, una vez',
        () async {
      final m = qr();
      await m.initialize();
      // La navegación deja el cobro arriba (lo que mira la pantalla del QR).
      when(nav.currentRoute).thenReturn(Routes.paymentView);
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(socket.stopTracking()).called(1);
      verify(nav.replaceWithPaymentView(orderId: 'o1')).called(1);
      m.dispose();
    });

    test(
        'si ya estaba entregado al abrir, va directo al cobro sin pedir código',
        () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      final m = qr();
      await m.initialize();
      verify(nav.replaceWithPaymentView(orderId: 'o1')).called(1);
      verifyNever(trips.deliveryCode(any));
      m.dispose();
    });

    test('el cliente cancela mientras se muestra el QR: avisa y vuelve',
        () async {
      final m = qr();
      await m.initialize();
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'cancelled'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(dialogs.showDialog(
              title: 'Pedido cancelado', description: anyNamed('description')))
          .called(1);
      expect(homeCalls, 1);
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      m.dispose();
    });

    test('sin código (400 del back) muestra el error y no hay polling',
        () async {
      when(trips.deliveryCode('o1')).thenThrow(http(
          400, {'message': 'El pedido todavía no tiene código de entrega'}));
      final m = qr();
      await m.initialize();
      expect(m.code, isNull);
      expect(m.loadError, 'El pedido todavía no tiene código de entrega');
      clearInteractions(trips);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verifyNever(trips.order(any));
      m.dispose();
    });

    test('red caída esperando: sigue esperando, no se rompe', () async {
      final m = qr();
      await m.initialize();
      when(trips.order('o1'))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(m.code, 'A1B2C3D4E5');
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      m.dispose();
    });

    test('sin timers vivos al salir', () async {
      final m = qr();
      await m.initialize();
      m.dispose();
      clearInteractions(trips);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verifyNever(trips.order(any));
    });
  });

  group('Cobro', () {
    PaymentViewModel pay() => PaymentViewModel(orderId: 'o1', trips: trips);

    test('efectivo: total a cobrar y "Pago recibido" sigue al cierre',
        () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      final m = pay();
      await m.load();
      expect(m.isCash, true);
      expect(m.confirmLabel, 'Pago recibido');
      await m.confirm();
      verify(nav.replaceWithCompletedView(orderId: 'o1')).called(1);
    });

    test('Mercado Pago: muestra el estado del pago según el back', () async {
      for (final (status, text) in [
        ('paid', 'Pagado por el cliente'),
        ('pending', 'Pendiente de pago del cliente'),
        ('failed', 'El pago falló'),
      ]) {
        when(trips.order('o1')).thenAnswer((_) async =>
            trip(status: 'delivered', method: 'online', paymentStatus: status));
        final m = pay();
        await m.load();
        expect(m.isCash, false);
        expect(m.confirmLabel, 'Continuar');
        expect(m.onlineStatus, text);
      }
    });

    test('error de carga: texto y reintento', () async {
      when(trips.order('o1')).thenThrow(http(500));
      final m = pay();
      await m.load();
      expect(m.order, isNull);
      expect(m.loadError, contains('servidor'));
    });
  });

  group('Calificar al cliente', () {
    CompletedViewModel done() => CompletedViewModel(
        orderId: 'o1', trips: trips, goHome: () => homeCalls++);

    test('sin estrellas no llama al back', () async {
      final m = done();
      expect(await m.submitRating(), false);
      expect(m.ratingError, 'Elegí de 1 a 5 estrellas.');
      verifyNever(trips.rateCustomer(any, any, any));
    });

    test('con estrellas y comentario llama a ratings y queda calificado',
        () async {
      final m = done();
      m.setStars(4);
      m.setComment('Muy amable');
      expect(await m.submitRating(), true);
      verify(trips.rateCustomer('o1', 4, 'Muy amable')).called(1);
      expect(m.rated, true);
      // No se califica dos veces.
      clearInteractions(trips);
      await m.submitRating();
      verifyNever(trips.rateCustomer(any, any, any));
    });

    test('409 "ya calificaste" se toma como hecho', () async {
      when(trips.rateCustomer('o1', 5, any))
          .thenThrow(http(409, {'message': 'Ya calificaste este pedido'}));
      final m = done();
      m.setStars(5);
      expect(await m.submitRating(), true);
      expect(m.ratingError, isNull);
    });

    test('un 409 de idempotencia en curso NO se toma como hecho', () async {
      when(trips.rateCustomer('o1', 5, any)).thenThrow(http(
          409, {'message': 'Request en curso con la misma Idempotency-Key'}));
      final m = done();
      m.setStars(5);
      expect(await m.submitRating(), false);
      expect(m.rated, false);
      expect(m.ratingError, isNotNull);
    });

    test('error de red: se muestra y se puede reintentar', () async {
      when(trips.rateCustomer('o1', 3, any))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '')));
      final m = done();
      m.setStars(3);
      expect(await m.submitRating(), false);
      expect(m.ratingError, 'Sin conexión. Revisá tu internet.');
      expect(m.submitting, false);
    });

    test('finish libera el flujo y vuelve al Inicio', () async {
      final m = CompletedViewModel(
          orderId: 'o1', trips: trips, goHome: () => homeCalls++, paid: true);
      await m.load();
      m.finish();
      verify(trips.endFlow()).called(1);
      expect(homeCalls, 1);
    });

    test('finish sin haber cargado el pedido libera el flujo', () {
      final m = done();
      m.finish();
      verify(trips.endFlow()).called(1);
      expect(homeCalls, 1);
    });
  });

  test('DriverOrderStatus usado por el cobro', () {
    expect(trip(status: 'delivered').status, DriverOrderStatus.delivered);
    expect(Routes.paymentView, isNotEmpty);
  });
}
