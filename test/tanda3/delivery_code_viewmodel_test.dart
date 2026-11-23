import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/delivery_code/delivery_code_viewmodel.dart';
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
  late MockLocationService loc;
  var homeCalls = 0;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    dialogs = locator<DialogService>() as MockDialogService;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    loc = locator<LocationService>() as MockLocationService;
    homeCalls = 0;
    // El cobro queda arriba apenas se pide abrirlo.
    when(nav.currentRoute).thenReturn(Routes.paymentView);
    when(trips.order('o1'))
        .thenAnswer((_) async => trip(status: 'out_for_delivery'));
    when(trips.customerRating(any)).thenAnswer((_) async => null);
    when(loc.locationBlock()).thenAnswer((_) async => null);
    when(loc.currentPosition).thenReturn(fix());
    when(trips.confirmDelivery(any,
            code: anyNamed('code'),
            latitude: anyNamed('latitude'),
            longitude: anyNamed('longitude'),
            accuracyMeters: anyNamed('accuracyMeters')))
        .thenAnswer((_) async {});
  });
  tearDown(() => locator.reset());

  DeliveryCodeViewModel vm() => DeliveryCodeViewModel(
      orderId: 'o1',
      trips: trips,
      pollInterval: const Duration(milliseconds: 20),
      goHome: () => homeCalls++);

  Future<DeliveryCodeViewModel> ready([String code = '482913']) async {
    final m = vm();
    await m.initialize();
    for (final d in code.split('')) {
      m.addDigit(d);
    }
    return m;
  }

  group('teclado', () {
    test('acumula hasta 6 dígitos, ignora lo que no es dígito y borra',
        () async {
      final m = await ready('4829');
      expect(m.digits, '4829');
      expect(m.complete, isFalse);
      expect(m.canSubmit, isFalse);
      m.addDigit('a');
      m.addDigit('12');
      expect(m.digits, '4829');
      m.addDigit('1');
      m.addDigit('3');
      m.addDigit('7');
      expect(m.digits, '482913');
      expect(m.canSubmit, isTrue);
      expect(m.spokenDigits, '4 8 2 9 1 3');
      m.deleteDigit();
      expect(m.digits, '48291');
      expect(m.canSubmit, isFalse);
      m.dispose();
    });
  });

  group('confirmar entrega', () {
    test('manda código + ubicación actual y sigue al cobro', () async {
      final m = await ready();
      await m.submit();
      verify(trips.confirmDelivery('o1',
              code: '482913',
              latitude: -27.357482,
              longitude: -55.890404,
              accuracyMeters: 5))
          .called(1);
      verify(nav.replaceWithPaymentView(orderId: 'o1')).called(1);
      verify(trips.paymentOpenedFor = 'o1').called(1);
      expect(m.errorMessage, isNull);
      m.dispose();
    });

    test('si el cobro no se abre, no se marca y sigue en la pantalla',
        () async {
      when(nav.currentRoute).thenReturn('/otra');
      final m = await ready();
      await m.submit();
      verifyNever(trips.paymentOpenedFor = 'o1');
      m.dispose();
    });

    test('sin 6 dígitos no llama al back', () async {
      final m = await ready('4829');
      await m.submit();
      verifyNever(trips.confirmDelivery(any,
          code: anyNamed('code'),
          latitude: anyNamed('latitude'),
          longitude: anyNamed('longitude'),
          accuracyMeters: anyNamed('accuracyMeters')));
      m.dispose();
    });

    test('si ya estaba entregado al abrir, va al cobro sin pedir código',
        () async {
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      final m = vm();
      await m.initialize();
      verify(nav.replaceWithPaymentView(orderId: 'o1')).called(1);
      verifyNever(trips.confirmDelivery(any,
          code: anyNamed('code'),
          latitude: anyNamed('latitude'),
          longitude: anyNamed('longitude'),
          accuracyMeters: anyNamed('accuracyMeters')));
      m.dispose();
    });

    test('código incorrecto con intentos restantes: lo dice y limpia',
        () async {
      when(trips.confirmDelivery(any,
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(http(400, {
        'code': 'DELIVERY_CODE_INCORRECTO',
        'message': 'Código incorrecto',
        'remaining': 3,
      }));
      final m = await ready();
      await m.submit();
      expect(m.errorMessage, 'El código no es correcto. Te quedan 3 intentos.');
      expect(m.digits, '');
      expect(m.blocked, isFalse);
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      m.dispose();
    });

    test('código incorrecto sin dato de intentos: sólo el aviso', () async {
      when(trips.confirmDelivery(any,
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(http(400, {'code': 'DELIVERY_CODE_INCORRECTO'}));
      final m = await ready();
      await m.submit();
      expect(m.errorMessage, kCodeIncorrectText);
      m.dispose();
    });

    test('formato inválido', () async {
      when(trips.confirmDelivery(any,
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(http(400, {'code': 'DELIVERY_CODE_FORMATO'}));
      final m = await ready();
      await m.submit();
      expect(m.errorMessage, kCodeFormatText);
      m.dispose();
    });

    test('bloqueado: avisa, deshabilita el teclado y no avanza', () async {
      when(trips.confirmDelivery(any,
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(http(409, {'code': 'DELIVERY_CODE_BLOQUEADO'}));
      final m = await ready();
      await m.submit();
      expect(m.blocked, isTrue);
      expect(m.errorMessage, kCodeBlockedText);
      expect(m.canSubmit, isFalse);
      m.addDigit('1');
      expect(m.digits, '482913');
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      m.dispose();
    });

    test('pedido que ya no está en camino: lo dice y no cuenta como éxito',
        () async {
      when(trips.confirmDelivery(any,
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(http(409, {'code': 'ORDER_NOT_ON_THE_WAY'}));
      final m = await ready();
      await m.submit();
      expect(m.errorMessage, kOrderNotOnTheWayText);
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      m.dispose();
    });

    test('403: no es su pedido', () async {
      when(trips.confirmDelivery(any,
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(http(403, {'message': 'Forbidden'}));
      final m = await ready();
      await m.submit();
      expect(m.errorMessage, kNotYourOrderText);
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      m.dispose();
    });

    test('red caída o 5xx: error, conserva el código para reintentar',
        () async {
      when(trips.confirmDelivery(any,
              code: anyNamed('code'),
              latitude: anyNamed('latitude'),
              longitude: anyNamed('longitude'),
              accuracyMeters: anyNamed('accuracyMeters')))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '')));
      final m = await ready();
      await m.submit();
      expect(m.errorMessage, isNotNull);
      expect(m.digits, '482913');
      expect(m.sending, isFalse);
      expect(m.canSubmit, isTrue);
      verifyNever(nav.replaceWithPaymentView(orderId: 'o1'));
      m.dispose();
    });

    test('sin ubicación: no llama al back y lo explica', () async {
      when(loc.locationBlock())
          .thenAnswer((_) async => LocationBlock.serviceDisabled);
      final m = await ready();
      await m.submit();
      expect(m.errorMessage, contains('GPS apagado'));
      expect(m.digits, '482913');
      verifyNever(trips.confirmDelivery(any,
          code: anyNamed('code'),
          latitude: anyNamed('latitude'),
          longitude: anyNamed('longitude'),
          accuracyMeters: anyNamed('accuracyMeters')));
      m.dispose();
    });

    test('permiso denegado: lo pide y, si lo dan, lee el GPS y manda',
        () async {
      var llamadas = 0;
      when(loc.locationBlock()).thenAnswer(
          (_) async => llamadas++ == 0 ? LocationBlock.permissionDenied : null);
      when(loc.requestLocationPermission()).thenAnswer((_) async => true);
      when(loc.readFreshPosition(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => PositionRead.ok(fix()));
      final m = await ready();
      await m.submit();
      verify(loc.requestLocationPermission()).called(1);
      verify(nav.replaceWithPaymentView(orderId: 'o1')).called(1);
      m.dispose();
    });
  });

  group('pedido en curso', () {
    test('cancelado mientras escribe: avisa y vuelve', () async {
      final m = await ready('48');
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'cancelled'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(dialogs.showDialog(
              title: 'Pedido cancelado', description: anyNamed('description')))
          .called(1);
      expect(homeCalls, 1);
      m.dispose();
    });

    test('entregado desde otro lado: sigue al cobro, una vez', () async {
      final m = await ready('48');
      when(trips.order('o1'))
          .thenAnswer((_) async => trip(status: 'delivered'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(socket.stopTracking()).called(1);
      verify(nav.replaceWithPaymentView(orderId: 'o1')).called(1);
      m.dispose();
    });

    test('sin timers vivos al salir', () async {
      final m = await ready();
      m.dispose();
      clearInteractions(trips);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verifyNever(trips.order(any));
    });
  });
}
