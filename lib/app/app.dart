import 'package:driver_mobile/ui/dialogs/info_alert/info_alert_dialog.dart';
import 'package:driver_mobile/ui/dialogs/order_offer/order_offer_dialog.dart';
import 'package:driver_mobile/ui/views/home/home_view.dart';
import 'package:driver_mobile/ui/views/startup/startup_view.dart';
import 'package:stacked/stacked_annotations.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:driver_mobile/ui/views/login/login_view.dart';
import 'package:driver_mobile/services/order_service.dart';
import 'package:driver_mobile/ui/views/directions/directions_view.dart';
import 'package:driver_mobile/ui/bottom_sheets/order_info/order_info_sheet.dart';
import 'package:driver_mobile/services/location_service.dart';
import 'package:driver_mobile/services/driver_socket_service.dart';
import 'package:driver_mobile/services/driver_auth_service.dart';
// @stacked-import

@StackedApp(
  routes: [
    MaterialRoute(page: HomeView),
    MaterialRoute(page: StartupView),
    MaterialRoute(page: LoginView),
    MaterialRoute(page: DirectionsView),
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
