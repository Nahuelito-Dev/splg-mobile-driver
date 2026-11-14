// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// StackedLocatorGenerator
// **************************************************************************

// ignore_for_file: public_member_api_docs, implementation_imports, depend_on_referenced_packages

import 'package:stacked_services/src/bottom_sheet/bottom_sheet_service.dart';
import 'package:stacked_services/src/dialog/dialog_service.dart';
import 'package:stacked_services/src/navigation/navigation_service.dart';
import 'package:stacked_shared/stacked_shared.dart';

import '../services/app_permissions.dart';
import '../services/delivery_offer_slot.dart';
import '../services/driver_api_service.dart';
import '../services/driver_auth_service.dart';
import '../services/driver_ops_repository.dart';
import '../services/driver_socket_service.dart';
import '../services/fcm_service.dart';
import '../services/foreground_service.dart';
import '../services/location_service.dart';
import '../services/maintenance_board.dart';
import '../services/maintenance_notifier.dart';
import '../services/maintenance_repository.dart';
import '../services/payment_repository.dart';
import '../services/recovery_repository.dart';
import '../services/route_batch_repository.dart';
import '../services/trip_service.dart';

final locator = StackedLocator.instance;

Future<void> setupLocator({
  String? environment,
  EnvironmentFilter? environmentFilter,
}) async {
// Register environments
  locator.registerEnvironment(
      environment: environment, environmentFilter: environmentFilter);

// Register dependencies
  locator.registerLazySingleton(() => BottomSheetService());
  locator.registerLazySingleton(() => DialogService());
  locator.registerLazySingleton(() => NavigationService());
  locator.registerLazySingleton(() => LocationService());
  locator.registerLazySingleton(() => DriverSocketService());
  locator.registerLazySingleton(() => DriverAuthService());
  locator.registerLazySingleton(() => DriverForegroundService());
  locator.registerLazySingleton(() => FcmService());
  locator.registerLazySingleton(() => AppPermissions());
  locator.registerLazySingleton(() => DriverApiService());
  locator.registerLazySingleton(() => TripService());
  locator
      .registerLazySingleton<PaymentRepository>(() => HttpPaymentRepository());
  locator.registerLazySingleton<DriverOpsRepository>(
      () => HttpDriverOpsRepository());
  locator.registerLazySingleton<MaintenanceRepository>(
      () => HttpMaintenanceRepository());
  locator.registerLazySingleton(() => MaintenanceBoard());
  locator.registerLazySingleton(() => MaintenanceNotifier());
  locator.registerLazySingleton<RouteBatchRepository>(
      () => HttpRouteBatchRepository());
  locator.registerLazySingleton<RecoveryRepository>(
      () => HttpRecoveryRepository());
  locator.registerLazySingleton(() => DeliveryOfferSlot());
}
