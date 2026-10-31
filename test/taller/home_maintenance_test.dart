import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'package:splg_driver/services/maintenance_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

/// El Inicio le delega los avisos de taller a `MaintenanceNotifier`: acá se
/// verifica el cableado (en línea, oferta de pedido, resumen, cierre de sesión).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockMaintenanceNotifier notifier;
  late MockMaintenanceBoard board;
  late MockMaintenanceRepository repo;
  late MockDriverSocketService socket;
  late MockDialogService dialogs;
  late MockTripService trips;
  late StreamController<Map<String, dynamic>> offers;

  setUp(() {
    registerServices();
    notifier = locator<MaintenanceNotifier>() as MockMaintenanceNotifier;
    board = locator<MaintenanceBoard>() as MockMaintenanceBoard;
    repo = locator<MaintenanceRepository>() as MockMaintenanceRepository;
    socket = locator<DriverSocketService>() as MockDriverSocketService;
    dialogs = locator<DialogService>() as MockDialogService;
    trips = locator<TripService>() as MockTripService;
    final auth = locator<DriverAuthService>() as MockDriverAuthService;
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
    when(socket.isConnected).thenReturn(false);
    when(socket.hasSocket).thenReturn(false);
    when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
    offers = StreamController<Map<String, dynamic>>.broadcast();
    when(socket.incomingOrders).thenAnswer((_) => offers.stream);
    when(trips.activeOrderId).thenReturn(null);
    when(notifier.pending).thenReturn(const []);
  });
  tearDown(() async {
    await offers.close();
    locator.reset();
  });

  HomeViewModel home() {
    final api = MockApiClient();
    when(api.patch(any, any, any)).thenAnswer(
        (_) async => Response(requestOptions: RequestOptions(path: '')));
    return HomeViewModel(trips: trips, apiClient: api);
  }

  test('al ponerse en línea ata el tablero al chofer, escucha y lee pendientes',
      () async {
    final m = home();
    await m.connect();
    verify(board.bind('u1')).called(1);
    verify(board.attach(any)).called(1);
    verify(notifier.start()).called(1);
    verify(notifier.sync()).called(greaterThanOrEqualTo(1));
  });

  test('al desconectarse deja de escuchar y se cierran los avisos', () async {
    final m = home();
    await m.connect();
    await m.disconnect();
    verify(notifier.stop()).called(greaterThanOrEqualTo(1));
    verify(board.detach()).called(greaterThanOrEqualTo(1));
  });

  test('la oferta de pedido le avisa al notificador antes y después', () async {
    final gate = Completer<DialogResponse?>();
    when(dialogs.showCustomDialog(
            variant: anyNamed('variant'),
            data: anyNamed('data'),
            barrierDismissible: anyNamed('barrierDismissible')))
        .thenAnswer((_) => gate.future);
    final m = home();
    await m.connect();
    offers.add({'orderId': 'o1'});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    verify(notifier.offerStarted()).called(1);
    verifyNever(notifier.offerEnded());
    gate.complete(DialogResponse(confirmed: false));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    verify(notifier.offerEnded()).called(1);
    verify(trips.reject('o1')).called(1);
  });

  test('una oferta rechazada por ocupado no toca al notificador', () async {
    when(trips.activeOrderId).thenReturn('en-curso');
    final m = home();
    await m.connect();
    offers.add({'orderId': 'o2'});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    verifyNever(notifier.offerStarted());
  });

  test('la marca del Inicio sale de las pendientes, también fuera de línea',
      () {
    final m = home();
    expect(m.pendingMaintenance, 0);
    when(notifier.pending).thenReturn([
      MaintenanceProposal.fromJson({
        'proposalId': 'p1',
        'windowStart': '2026-11-04T11:00:00.000Z',
        'windowEnd': '2026-11-04T15:00:00.000Z',
        'expiresAt': '2026-11-03T13:00:00.000Z',
      })
    ]);
    expect(m.pendingMaintenance, 1);
  });

  test('al volver a primer plano relee las pendientes', () async {
    final m = home();
    m.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    verify(notifier.sync()).called(greaterThanOrEqualTo(1));
  });

  test('cerrar sesión descarta lo del chofer (avisos, tablero, claves)',
      () async {
    final m = home();
    await m.connect();
    await m.logout();
    verify(notifier.reset()).called(1);
    verify(board.reset()).called(1);
    verify(repo.reset()).called(1);
  });

  test('abrir Taller no apila otra pantalla: lo decide el notificador',
      () async {
    final m = home();
    await m.openTaller();
    verify(notifier.openTaller()).called(1);
  });
}
