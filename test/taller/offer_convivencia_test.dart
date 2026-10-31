import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.dialogs.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/maintenance_board.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'package:splg_driver/services/maintenance_repository.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/ui/dialogs/maintenance_proposal/route_notice_presenter.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';
import 'maintenance_logic_test.dart' as logic;

/// La oferta de pedido es la real: `DialogService.showCustomDialog` desde
/// `HomeViewModel._showOrderOfferDialog`, que se cierra con `completeDialog`
/// (`Get.back`: saca la ruta de más arriba de todo). Nada del taller puede
/// quedar encima de ella ni de un pedido en curso.
void main() {
  late MockDriverSocketService socket;
  late MockTripService trips;
  late MaintenanceBoard board;
  late MaintenanceNotifier notifier;
  late StreamController<Map<String, dynamic>> offers;
  late List<String> tallerOpened;
  String? active;

  setUp(() {
    registerServices();
    // DialogService REAL con la oferta como en la app: un diálogo que se cierra
    // con `completer` (= completeDialog).
    locator.unregister<DialogService>();
    final dialogs = DialogService();
    dialogs.registerCustomDialogBuilders({
      DialogType.orderOffer: (context, request, completer) => AlertDialog(
            content: const Text('OFERTA DE PEDIDO'),
            actions: [
              TextButton(
                key: const Key('offer-back'),
                onPressed: () => completer(DialogResponse(confirmed: false)),
                child: const Text('Volver'),
              ),
            ],
          ),
    });
    locator.registerSingleton<DialogService>(dialogs);

    socket = locator<DriverSocketService>() as MockDriverSocketService;
    trips = locator<TripService>() as MockTripService;
    final auth = locator<DriverAuthService>() as MockDriverAuthService;
    when(auth.token).thenAnswer((_) async => 'tok');
    when(auth.userId).thenReturn('u1');
    when(socket.isConnected).thenReturn(false);
    when(socket.hasSocket).thenReturn(false);
    when(socket.waitUntilConnected(any)).thenAnswer((_) async => true);
    offers = StreamController<Map<String, dynamic>>.broadcast();
    when(socket.incomingOrders).thenAnswer((_) => offers.stream);
    when(socket.maintenanceEvents)
        .thenAnswer((_) => const Stream<MaintenanceEvent>.empty());
    active = null;
    when(trips.activeOrderId).thenAnswer((_) => active);

    locator.unregister<MaintenanceBoard>();
    board = MaintenanceBoard();
    locator.registerSingleton<MaintenanceBoard>(board);
    tallerOpened = [];
    final repo = locator<MaintenanceRepository>() as MockMaintenanceRepository;
    when(repo.proposals(limit: anyNamed('limit'), offset: anyNamed('offset')))
        .thenAnswer((_) async => const MaintenancePage());
    locator.unregister<MaintenanceNotifier>();
    notifier = MaintenanceNotifier(
      board: board,
      repo: repo,
      presenter: RouteNoticePresenter(),
      dialogs: dialogs,
      openTallerRoute: () async {
        tallerOpened.add('taller');
        await StackedService.navigatorKey!.currentState!.push(
            MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('PANTALLA TALLER'))));
      },
    );
    locator.registerSingleton<MaintenanceNotifier>(notifier);
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

  Future<void> pumpApp(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      navigatorKey: StackedService.navigatorKey,
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: Text('INICIO')),
    ));
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      'push de Taller con una oferta abierta: espera; la oferta se resuelve y '
      'la siguiente no cae en «Ocupado»', (t) async {
    await pumpApp(t);
    final m = home();
    await m.connect();

    offers.add({'orderId': 'o1'});
    await settle(t);
    expect(find.text('OFERTA DE PEDIDO'), findsOneWidget);

    // El chofer toca la notificación «Taller» con la oferta abierta.
    await notifier.openTaller();
    await settle(t);
    expect(find.text('PANTALLA TALLER'), findsNothing,
        reason: 'nada del taller encima de la oferta');
    expect(tallerOpened, isEmpty);

    // La oferta se cierra con completeDialog (Get.back): sale la oferta.
    await t.tap(find.byKey(const Key('offer-back')));
    await settle(t);
    expect(find.text('OFERTA DE PEDIDO'), findsNothing);
    verify(trips.reject('o1')).called(1);

    // La intención guardada se ejecuta al terminar la oferta.
    expect(tallerOpened, ['taller']);
    expect(find.text('PANTALLA TALLER'), findsOneWidget);

    // La oferta siguiente se muestra: la oferta anterior no quedó "abierta".
    offers.add({'orderId': 'o2'});
    await settle(t);
    expect(find.text('OFERTA DE PEDIDO'), findsOneWidget);
    verifyNever(trips.reject('o2'));
    await t.tap(find.byKey(const Key('offer-back')));
    await settle(t);
    verify(trips.reject('o2')).called(1);
    notifier.dispose();
    await m.disconnect();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'el aviso de taller con la oferta arriba se oculta y la oferta '
      'se cierra bien; el aviso vuelve después', (t) async {
    await pumpApp(t);
    final m = home();
    await m.connect();
    board.handle(ProposalReceived(
        MaintenanceProposal.fromJson(logic.json(expires: _soon()))));
    await settle(t);
    expect(find.byKey(const Key('maintenance-notice-text')), findsOneWidget);

    offers.add({'orderId': 'o1'});
    await settle(t);
    expect(find.text('OFERTA DE PEDIDO'), findsOneWidget);
    expect(find.byKey(const Key('maintenance-notice-text')), findsNothing,
        reason: 'el aviso cedió ante la oferta');

    await t.tap(find.byKey(const Key('offer-back')));
    await settle(t);
    expect(find.text('OFERTA DE PEDIDO'), findsNothing);
    expect(find.byKey(const Key('maintenance-notice-text')), findsOneWidget,
        reason: 'el aviso vuelve cuando la oferta se resuelve');
    notifier.dispose();
    await m.disconnect();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('aviso durante un pedido en curso: no aparece hasta que termina',
      (t) async {
    await pumpApp(t);
    final m = home();
    await m.connect();
    active = 'o9'; // el admin le asignó un pedido, o se retomó uno
    board.handle(ProposalReceived(
        MaintenanceProposal.fromJson(logic.json(expires: _soon()))));
    await notifier.openTaller();
    await settle(t);
    expect(find.byKey(const Key('maintenance-notice-text')), findsNothing,
        reason: 'ni el aviso ni Taller encima del flujo de entrega');
    expect(tallerOpened, isEmpty);

    active = null;
    notifier.recheck(); // lo que hace el Inicio al terminar el flujo
    await settle(t);
    expect(find.byKey(const Key('maintenance-notice-text')), findsOneWidget);
    expect(tallerOpened, ['taller']);
    notifier.dispose();
    await m.disconnect();
    await t.pumpWidget(const SizedBox());
  });
}

String _soon() =>
    DateTime.now().toUtc().add(const Duration(hours: 3)).toIso8601String();
