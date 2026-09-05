import 'package:splg_driver/ui/dialogs/info_alert/info_alert_dialog.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';
import 'package:splg_driver/ui/views/startup/startup_view.dart';
import 'package:stacked/stacked_annotations.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:splg_driver/ui/views/login/login_view.dart';
import 'package:splg_driver/services/order_service.dart';
import 'package:splg_driver/ui/views/directions/directions_view.dart';
import 'package:splg_driver/ui/views/delivery/delivery_view.dart';
import 'package:splg_driver/ui/bottom_sheets/order_info/order_info_sheet.dart';
import 'package:splg_driver/ui/views/legal/legal_view.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/fcm_service.dart';
// @stacked-import

@StackedApp(
  routes: [
    MaterialRoute(page: HomeView),
    MaterialRoute(page: StartupView),
    MaterialRoute(page: LoginView),
    MaterialRoute(page: DirectionsView),
    MaterialRoute(page: DeliveryView),
    MaterialRoute(page: LegalView),
// @stacked-route
  ],
  dependencies: [
    LazySingleton(classType: BottomSheetService),
    LazySingleton(classType: DialogService),
    LazySingleton(classType: NavigationService),
    LazySingleton(classType: OrderService),
    LazySingleton(classType: LocationService),
    LazySingleton(classType: DriverSocketService),
    LazySingleton(classType: DriverAuthService),
    LazySingleton(classType: DriverForegroundService),
    LazySingleton(classType: FcmService),
// @stacked-service
  ],
  bottomsheets: [
    StackedBottomsheet(classType: OrderInfoSheet),
// @stacked-bottom-sheet
  ],
  dialogs: [
    StackedDialog(classType: InfoAlertDialog),
    StackedDialog(classType: OrderOfferDialog),
// @stacked-dialog
  ],
)
class App {}
