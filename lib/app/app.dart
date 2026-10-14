import 'package:splg_driver/ui/dialogs/info_alert/info_alert_dialog.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';
import 'package:splg_driver/ui/views/startup/startup_view.dart';
import 'package:stacked/stacked_annotations.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:splg_driver/ui/views/login/login_view.dart';
import 'package:splg_driver/ui/views/directions/directions_view.dart';
import 'package:splg_driver/ui/views/delivery/delivery_view.dart';
import 'package:splg_driver/ui/bottom_sheets/order_info/order_info_sheet.dart';
import 'package:splg_driver/ui/views/legal/legal_view.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/driver_auth_service.dart';
import 'package:splg_driver/services/foreground_service.dart';
import 'package:splg_driver/services/fcm_service.dart';
import 'package:splg_driver/services/app_permissions.dart';
import 'package:splg_driver/ui/views/welcome/welcome_view.dart';
import 'package:splg_driver/ui/views/forgot_password/forgot_password_view.dart';
import 'package:splg_driver/ui/views/profile/profile_view.dart';
import 'package:splg_driver/ui/views/personal_info/personal_info_view.dart';
import 'package:splg_driver/ui/views/change_password/change_password_view.dart';
import 'package:splg_driver/ui/views/deliveries/deliveries_view.dart';
import 'package:splg_driver/ui/views/delivery_detail/delivery_detail_view.dart';
import 'package:splg_driver/ui/views/vehicle/vehicle_view.dart';
import 'package:splg_driver/ui/views/earnings/earnings_view.dart';
import 'package:splg_driver/ui/views/rating/rating_view.dart';
import 'package:splg_driver/ui/views/notifications/notifications_view.dart';
import 'package:splg_driver/ui/views/help/help_view.dart';
import 'package:splg_driver/ui/views/about/about_view.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/trip_service.dart';
import 'package:splg_driver/services/payment_repository.dart';
import 'package:splg_driver/ui/views/delivery_qr/delivery_qr_view.dart';
import 'package:splg_driver/ui/views/payment/payment_view.dart';
import 'package:splg_driver/ui/views/completed/completed_view.dart';
import 'package:splg_driver/ui/views/my_load/my_load_view.dart';
import 'package:splg_driver/ui/views/pending_collections/pending_collections_view.dart';
// @stacked-import

@StackedApp(
  routes: [
    MaterialRoute(page: HomeView),
    MaterialRoute(page: StartupView),
    MaterialRoute(page: LoginView),
    MaterialRoute(page: DirectionsView),
    MaterialRoute(page: DeliveryView),
    MaterialRoute(page: LegalView),
    MaterialRoute(page: WelcomeView),
    MaterialRoute(page: ForgotPasswordView),
    MaterialRoute(page: ProfileView),
    MaterialRoute(page: PersonalInfoView),
    MaterialRoute(page: ChangePasswordView),
    MaterialRoute(page: DeliveriesView),
    MaterialRoute(page: DeliveryDetailView),
    MaterialRoute(page: VehicleView),
    MaterialRoute(page: EarningsView),
    MaterialRoute(page: RatingView),
    MaterialRoute(page: NotificationsView),
    MaterialRoute(page: HelpView),
    MaterialRoute(page: AboutView),
    MaterialRoute(page: DeliveryQrView),
    MaterialRoute(page: PaymentView),
    MaterialRoute(page: CompletedView),
    MaterialRoute(page: MyLoadView),
    MaterialRoute(page: PendingCollectionsView),
// @stacked-route
  ],
  dependencies: [
    LazySingleton(classType: BottomSheetService),
    LazySingleton(classType: DialogService),
    LazySingleton(classType: NavigationService),
    LazySingleton(classType: LocationService),
    LazySingleton(classType: DriverSocketService),
    LazySingleton(classType: DriverAuthService),
    LazySingleton(classType: DriverForegroundService),
    LazySingleton(classType: FcmService),
    LazySingleton(classType: AppPermissions),
    LazySingleton(classType: DriverApiService),
    LazySingleton(classType: TripService),
    LazySingleton(classType: HttpPaymentRepository, asType: PaymentRepository),
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
