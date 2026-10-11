import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:splg_driver/services/order_service.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/fcm_service.dart';
import 'package:splg_driver/services/app_permissions.dart';
import 'package:splg_driver/core/network/api_client.dart';
import 'package:splg_lib/permissions/app_permission.dart';
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/models/driver_data.dart';
// @stacked-import

import 'test_helpers.mocks.dart';

@GenerateMocks(
  [],
  customMocks: [
    MockSpec<NavigationService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<BottomSheetService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<DialogService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<OrderService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<LocationService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<DriverSocketService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<DriverAuthService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<DriverForegroundService>(
        onMissingStub: OnMissingStub.returnDefault),
    MockSpec<FcmService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<AppPermissions>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<ApiClient>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<DriverApiService>(onMissingStub: OnMissingStub.returnDefault),
// @stacked-mock-spec
  ],
)
void registerServices() {
  provideDummy<PermissionOutcome>(PermissionOutcome.granted);
  provideDummy<OrdersPage>(const OrdersPage(orders: [], total: 0, offset: 0));
  getAndRegisterNavigationService();
  getAndRegisterBottomSheetService();
  getAndRegisterDialogService();
  getAndRegisterOrderService();
  getAndRegisterLocationService();
  getAndRegisterDriverSocketService();
  getAndRegisterDriverAuthService();
  getAndRegisterDriverForegroundService();
  getAndRegisterFcmService();
  getAndRegisterAppPermissions();
  getAndRegisterDriverApiService();
// @stacked-mock-register
}

MockNavigationService getAndRegisterNavigationService() {
  _removeRegistrationIfExists<NavigationService>();
  final service = MockNavigationService();
  locator.registerSingleton<NavigationService>(service);
  return service;
}

MockBottomSheetService getAndRegisterBottomSheetService<T>({
  SheetResponse<T>? showCustomSheetResponse,
}) {
  _removeRegistrationIfExists<BottomSheetService>();
  final service = MockBottomSheetService();

  when(
    service.showCustomSheet<T, T>(
      enableDrag: anyNamed('enableDrag'),
      enterBottomSheetDuration: anyNamed('enterBottomSheetDuration'),
      exitBottomSheetDuration: anyNamed('exitBottomSheetDuration'),
      ignoreSafeArea: anyNamed('ignoreSafeArea'),
      isScrollControlled: anyNamed('isScrollControlled'),
      barrierDismissible: anyNamed('barrierDismissible'),
      additionalButtonTitle: anyNamed('additionalButtonTitle'),
      variant: anyNamed('variant'),
      title: anyNamed('title'),
      hasImage: anyNamed('hasImage'),
      imageUrl: anyNamed('imageUrl'),
      showIconInMainButton: anyNamed('showIconInMainButton'),
      mainButtonTitle: anyNamed('mainButtonTitle'),
      showIconInSecondaryButton: anyNamed('showIconInSecondaryButton'),
      secondaryButtonTitle: anyNamed('secondaryButtonTitle'),
      showIconInAdditionalButton: anyNamed('showIconInAdditionalButton'),
      takesInput: anyNamed('takesInput'),
      barrierColor: anyNamed('barrierColor'),
      barrierLabel: anyNamed('barrierLabel'),
      customData: anyNamed('customData'),
      data: anyNamed('data'),
      description: anyNamed('description'),
    ),
  ).thenAnswer(
    (realInvocation) =>
        Future.value(showCustomSheetResponse ?? SheetResponse<T>()),
  );

  locator.registerSingleton<BottomSheetService>(service);
  return service;
}

MockDialogService getAndRegisterDialogService() {
  _removeRegistrationIfExists<DialogService>();
  final service = MockDialogService();
  locator.registerSingleton<DialogService>(service);
  return service;
}

MockOrderService getAndRegisterOrderService() {
  _removeRegistrationIfExists<OrderService>();
  final service = MockOrderService();
  locator.registerSingleton<OrderService>(service);
  return service;
}

MockLocationService getAndRegisterLocationService() {
  _removeRegistrationIfExists<LocationService>();
  final service = MockLocationService();
  locator.registerSingleton<LocationService>(service);
  return service;
}

MockDriverSocketService getAndRegisterDriverSocketService() {
  _removeRegistrationIfExists<DriverSocketService>();
  final service = MockDriverSocketService();
  locator.registerSingleton<DriverSocketService>(service);
  return service;
}

MockDriverAuthService getAndRegisterDriverAuthService() {
  _removeRegistrationIfExists<DriverAuthService>();
  final service = MockDriverAuthService();
  locator.registerSingleton<DriverAuthService>(service);
  return service;
}

MockDriverApiService getAndRegisterDriverApiService() {
  _removeRegistrationIfExists<DriverApiService>();
  final service = MockDriverApiService();
  locator.registerSingleton<DriverApiService>(service);
  return service;
}

MockDriverForegroundService getAndRegisterDriverForegroundService() {
  _removeRegistrationIfExists<DriverForegroundService>();
  final service = MockDriverForegroundService();
  locator.registerSingleton<DriverForegroundService>(service);
  return service;
}
// @stacked-mock-create

void _removeRegistrationIfExists<T extends Object>() {
  if (locator.isRegistered<T>()) {
    locator.unregister<T>();
  }
}

MockFcmService getAndRegisterFcmService() {
  _removeRegistrationIfExists<FcmService>();
  final service = MockFcmService();
  locator.registerSingleton<FcmService>(service);
  return service;
}

MockAppPermissions getAndRegisterAppPermissions() {
  _removeRegistrationIfExists<AppPermissions>();
  final service = MockAppPermissions();
  locator.registerSingleton<AppPermissions>(service);
  return service;
}
