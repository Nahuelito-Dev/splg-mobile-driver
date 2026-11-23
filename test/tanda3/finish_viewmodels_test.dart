import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/completed/completed_viewmodel.dart';
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
  var homeCalls = 0;

  setUp(() {
    registerServices();
    trips = locator<TripService>() as MockTripService;
    nav = locator<NavigationService>() as MockNavigationService;
    homeCalls = 0;
    when(trips.order('o1'))
        .thenAnswer((_) async => trip(status: 'out_for_delivery'));
    when(trips.customerRating(any)).thenAnswer((_) async => null);
  });
  tearDown(() => locator.reset());

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
