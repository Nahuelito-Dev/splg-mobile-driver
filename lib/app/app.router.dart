// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// StackedNavigatorGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/material.dart' as _i26;
import 'package:flutter/material.dart';
import 'package:splg_driver/models/driver_data.dart' as _i27;
import 'package:splg_driver/ui/views/about/about_view.dart' as _i20;
import 'package:splg_driver/ui/views/change_password/change_password_view.dart'
    as _i12;
import 'package:splg_driver/ui/views/completed/completed_view.dart' as _i23;
import 'package:splg_driver/ui/views/deliveries/deliveries_view.dart' as _i13;
import 'package:splg_driver/ui/views/delivery/delivery_view.dart' as _i6;
import 'package:splg_driver/ui/views/delivery_detail/delivery_detail_view.dart'
    as _i14;
import 'package:splg_driver/ui/views/delivery_qr/delivery_qr_view.dart' as _i21;
import 'package:splg_driver/ui/views/directions/directions_view.dart' as _i5;
import 'package:splg_driver/ui/views/earnings/earnings_view.dart' as _i16;
import 'package:splg_driver/ui/views/forgot_password/forgot_password_view.dart'
    as _i9;
import 'package:splg_driver/ui/views/help/help_view.dart' as _i19;
import 'package:splg_driver/ui/views/home/home_view.dart' as _i2;
import 'package:splg_driver/ui/views/legal/legal_view.dart' as _i7;
import 'package:splg_driver/ui/views/login/login_view.dart' as _i4;
import 'package:splg_driver/ui/views/my_load/my_load_view.dart' as _i24;
import 'package:splg_driver/ui/views/notifications/notifications_view.dart'
    as _i18;
import 'package:splg_driver/ui/views/payment/payment_view.dart' as _i22;
import 'package:splg_driver/ui/views/pending_collections/pending_collections_view.dart'
    as _i25;
import 'package:splg_driver/ui/views/personal_info/personal_info_view.dart'
    as _i11;
import 'package:splg_driver/ui/views/profile/profile_view.dart' as _i10;
import 'package:splg_driver/ui/views/rating/rating_view.dart' as _i17;
import 'package:splg_driver/ui/views/startup/startup_view.dart' as _i3;
import 'package:splg_driver/ui/views/vehicle/vehicle_view.dart' as _i15;
import 'package:splg_driver/ui/views/welcome/welcome_view.dart' as _i8;
import 'package:stacked/stacked.dart' as _i1;
import 'package:stacked_services/stacked_services.dart' as _i28;

class Routes {
  static const homeView = '/home-view';

  static const startupView = '/startup-view';

  static const loginView = '/login-view';

  static const directionsView = '/directions-view';

  static const deliveryView = '/delivery-view';

  static const legalView = '/legal-view';

  static const welcomeView = '/welcome-view';

  static const forgotPasswordView = '/forgot-password-view';

  static const profileView = '/profile-view';

  static const personalInfoView = '/personal-info-view';

  static const changePasswordView = '/change-password-view';

  static const deliveriesView = '/deliveries-view';

  static const deliveryDetailView = '/delivery-detail-view';

  static const vehicleView = '/vehicle-view';

  static const earningsView = '/earnings-view';

  static const ratingView = '/rating-view';

  static const notificationsView = '/notifications-view';

  static const helpView = '/help-view';

  static const aboutView = '/about-view';

  static const deliveryQrView = '/delivery-qr-view';

  static const paymentView = '/payment-view';

  static const completedView = '/completed-view';

  static const myLoadView = '/my-load-view';

  static const pendingCollectionsView = '/pending-collections-view';

  static const all = <String>{
    homeView,
    startupView,
    loginView,
    directionsView,
    deliveryView,
    legalView,
    welcomeView,
    forgotPasswordView,
    profileView,
    personalInfoView,
    changePasswordView,
    deliveriesView,
    deliveryDetailView,
    vehicleView,
    earningsView,
    ratingView,
    notificationsView,
    helpView,
    aboutView,
    deliveryQrView,
    paymentView,
    completedView,
    myLoadView,
    pendingCollectionsView,
  };
}

class StackedRouter extends _i1.RouterBase {
  final _routes = <_i1.RouteDef>[
    _i1.RouteDef(Routes.homeView, page: _i2.HomeView),
    _i1.RouteDef(Routes.startupView, page: _i3.StartupView),
    _i1.RouteDef(Routes.loginView, page: _i4.LoginView),
    _i1.RouteDef(Routes.directionsView, page: _i5.DirectionsView),
    _i1.RouteDef(Routes.deliveryView, page: _i6.DeliveryView),
    _i1.RouteDef(Routes.legalView, page: _i7.LegalView),
    _i1.RouteDef(Routes.welcomeView, page: _i8.WelcomeView),
    _i1.RouteDef(Routes.forgotPasswordView, page: _i9.ForgotPasswordView),
    _i1.RouteDef(Routes.profileView, page: _i10.ProfileView),
    _i1.RouteDef(Routes.personalInfoView, page: _i11.PersonalInfoView),
    _i1.RouteDef(Routes.changePasswordView, page: _i12.ChangePasswordView),
    _i1.RouteDef(Routes.deliveriesView, page: _i13.DeliveriesView),
    _i1.RouteDef(Routes.deliveryDetailView, page: _i14.DeliveryDetailView),
    _i1.RouteDef(Routes.vehicleView, page: _i15.VehicleView),
    _i1.RouteDef(Routes.earningsView, page: _i16.EarningsView),
    _i1.RouteDef(Routes.ratingView, page: _i17.RatingView),
    _i1.RouteDef(Routes.notificationsView, page: _i18.NotificationsView),
    _i1.RouteDef(Routes.helpView, page: _i19.HelpView),
    _i1.RouteDef(Routes.aboutView, page: _i20.AboutView),
    _i1.RouteDef(Routes.deliveryQrView, page: _i21.DeliveryQrView),
    _i1.RouteDef(Routes.paymentView, page: _i22.PaymentView),
    _i1.RouteDef(Routes.completedView, page: _i23.CompletedView),
    _i1.RouteDef(Routes.myLoadView, page: _i24.MyLoadView),
    _i1.RouteDef(
      Routes.pendingCollectionsView,
      page: _i25.PendingCollectionsView,
    ),
  ];

  final _pagesMap = <Type, _i1.StackedRouteFactory>{
    _i2.HomeView: (data) {
      final args = data.getArgs<HomeViewArguments>(
        orElse: () => const HomeViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i2.HomeView(key: args.key),
        settings: data,
      );
    },
    _i3.StartupView: (data) {
      final args = data.getArgs<StartupViewArguments>(
        orElse: () => const StartupViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i3.StartupView(key: args.key),
        settings: data,
      );
    },
    _i4.LoginView: (data) {
      final args = data.getArgs<LoginViewArguments>(
        orElse: () => const LoginViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i4.LoginView(key: args.key),
        settings: data,
      );
    },
    _i5.DirectionsView: (data) {
      final args = data.getArgs<DirectionsViewArguments>(
        orElse: () => const DirectionsViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i5.DirectionsView(key: args.key),
        settings: data,
      );
    },
    _i6.DeliveryView: (data) {
      final args = data.getArgs<DeliveryViewArguments>(nullOk: false);
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) =>
            _i6.DeliveryView(key: args.key, orderId: args.orderId),
        settings: data,
      );
    },
    _i7.LegalView: (data) {
      final args = data.getArgs<LegalViewArguments>(nullOk: false);
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) =>
            _i7.LegalView(key: args.key, document: args.document),
        settings: data,
      );
    },
    _i8.WelcomeView: (data) {
      final args = data.getArgs<WelcomeViewArguments>(
        orElse: () => const WelcomeViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i8.WelcomeView(key: args.key),
        settings: data,
      );
    },
    _i9.ForgotPasswordView: (data) {
      final args = data.getArgs<ForgotPasswordViewArguments>(
        orElse: () => const ForgotPasswordViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) =>
            _i9.ForgotPasswordView(key: args.key, email: args.email),
        settings: data,
      );
    },
    _i10.ProfileView: (data) {
      final args = data.getArgs<ProfileViewArguments>(
        orElse: () => const ProfileViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i10.ProfileView(key: args.key),
        settings: data,
      );
    },
    _i11.PersonalInfoView: (data) {
      final args = data.getArgs<PersonalInfoViewArguments>(
        orElse: () => const PersonalInfoViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i11.PersonalInfoView(key: args.key),
        settings: data,
      );
    },
    _i12.ChangePasswordView: (data) {
      final args = data.getArgs<ChangePasswordViewArguments>(
        orElse: () => const ChangePasswordViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i12.ChangePasswordView(key: args.key),
        settings: data,
      );
    },
    _i13.DeliveriesView: (data) {
      final args = data.getArgs<DeliveriesViewArguments>(
        orElse: () => const DeliveriesViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i13.DeliveriesView(key: args.key),
        settings: data,
      );
    },
    _i14.DeliveryDetailView: (data) {
      final args = data.getArgs<DeliveryDetailViewArguments>(nullOk: false);
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) =>
            _i14.DeliveryDetailView(key: args.key, order: args.order),
        settings: data,
      );
    },
    _i15.VehicleView: (data) {
      final args = data.getArgs<VehicleViewArguments>(
        orElse: () => const VehicleViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i15.VehicleView(key: args.key),
        settings: data,
      );
    },
    _i16.EarningsView: (data) {
      final args = data.getArgs<EarningsViewArguments>(
        orElse: () => const EarningsViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i16.EarningsView(key: args.key),
        settings: data,
      );
    },
    _i17.RatingView: (data) {
      final args = data.getArgs<RatingViewArguments>(
        orElse: () => const RatingViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i17.RatingView(key: args.key),
        settings: data,
      );
    },
    _i18.NotificationsView: (data) {
      final args = data.getArgs<NotificationsViewArguments>(
        orElse: () => const NotificationsViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i18.NotificationsView(key: args.key),
        settings: data,
      );
    },
    _i19.HelpView: (data) {
      final args = data.getArgs<HelpViewArguments>(
        orElse: () => const HelpViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i19.HelpView(key: args.key),
        settings: data,
      );
    },
    _i20.AboutView: (data) {
      final args = data.getArgs<AboutViewArguments>(
        orElse: () => const AboutViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i20.AboutView(key: args.key),
        settings: data,
      );
    },
    _i21.DeliveryQrView: (data) {
      final args = data.getArgs<DeliveryQrViewArguments>(nullOk: false);
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) =>
            _i21.DeliveryQrView(key: args.key, orderId: args.orderId),
        settings: data,
      );
    },
    _i22.PaymentView: (data) {
      final args = data.getArgs<PaymentViewArguments>(nullOk: false);
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) =>
            _i22.PaymentView(key: args.key, orderId: args.orderId),
        settings: data,
      );
    },
    _i23.CompletedView: (data) {
      final args = data.getArgs<CompletedViewArguments>(nullOk: false);
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i23.CompletedView(
          key: args.key,
          orderId: args.orderId,
          unpaid: args.unpaid,
          paid: args.paid,
          photoFailed: args.photoFailed,
        ),
        settings: data,
      );
    },
    _i24.MyLoadView: (data) {
      final args = data.getArgs<MyLoadViewArguments>(
        orElse: () => const MyLoadViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i24.MyLoadView(key: args.key),
        settings: data,
      );
    },
    _i25.PendingCollectionsView: (data) {
      final args = data.getArgs<PendingCollectionsViewArguments>(
        orElse: () => const PendingCollectionsViewArguments(),
      );
      return _i26.MaterialPageRoute<dynamic>(
        builder: (context) => _i25.PendingCollectionsView(key: args.key),
        settings: data,
      );
    },
  };

  @override
  List<_i1.RouteDef> get routes => _routes;

  @override
  Map<Type, _i1.StackedRouteFactory> get pagesMap => _pagesMap;
}

class HomeViewArguments {
  const HomeViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant HomeViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class StartupViewArguments {
  const StartupViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant StartupViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class LoginViewArguments {
  const LoginViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant LoginViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class DirectionsViewArguments {
  const DirectionsViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant DirectionsViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class DeliveryViewArguments {
  const DeliveryViewArguments({this.key, required this.orderId});

  final _i26.Key? key;

  final String orderId;

  @override
  String toString() {
    return '{"key": "$key", "orderId": "$orderId"}';
  }

  @override
  bool operator ==(covariant DeliveryViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key && other.orderId == orderId;
  }

  @override
  int get hashCode {
    return key.hashCode ^ orderId.hashCode;
  }
}

class LegalViewArguments {
  const LegalViewArguments({this.key, required this.document});

  final _i26.Key? key;

  final _i7.LegalDocument document;

  @override
  String toString() {
    return '{"key": "$key", "document": "$document"}';
  }

  @override
  bool operator ==(covariant LegalViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key && other.document == document;
  }

  @override
  int get hashCode {
    return key.hashCode ^ document.hashCode;
  }
}

class WelcomeViewArguments {
  const WelcomeViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant WelcomeViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class ForgotPasswordViewArguments {
  const ForgotPasswordViewArguments({this.key, this.email});

  final _i26.Key? key;

  final String? email;

  @override
  String toString() {
    return '{"key": "$key", "email": "$email"}';
  }

  @override
  bool operator ==(covariant ForgotPasswordViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key && other.email == email;
  }

  @override
  int get hashCode {
    return key.hashCode ^ email.hashCode;
  }
}

class ProfileViewArguments {
  const ProfileViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant ProfileViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class PersonalInfoViewArguments {
  const PersonalInfoViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant PersonalInfoViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class ChangePasswordViewArguments {
  const ChangePasswordViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant ChangePasswordViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class DeliveriesViewArguments {
  const DeliveriesViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant DeliveriesViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class DeliveryDetailViewArguments {
  const DeliveryDetailViewArguments({this.key, required this.order});

  final _i26.Key? key;

  final _i27.DriverOrder order;

  @override
  String toString() {
    return '{"key": "$key", "order": "$order"}';
  }

  @override
  bool operator ==(covariant DeliveryDetailViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key && other.order == order;
  }

  @override
  int get hashCode {
    return key.hashCode ^ order.hashCode;
  }
}

class VehicleViewArguments {
  const VehicleViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant VehicleViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class EarningsViewArguments {
  const EarningsViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant EarningsViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class RatingViewArguments {
  const RatingViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant RatingViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class NotificationsViewArguments {
  const NotificationsViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant NotificationsViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class HelpViewArguments {
  const HelpViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant HelpViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class AboutViewArguments {
  const AboutViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant AboutViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class DeliveryQrViewArguments {
  const DeliveryQrViewArguments({this.key, required this.orderId});

  final _i26.Key? key;

  final String orderId;

  @override
  String toString() {
    return '{"key": "$key", "orderId": "$orderId"}';
  }

  @override
  bool operator ==(covariant DeliveryQrViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key && other.orderId == orderId;
  }

  @override
  int get hashCode {
    return key.hashCode ^ orderId.hashCode;
  }
}

class PaymentViewArguments {
  const PaymentViewArguments({this.key, required this.orderId});

  final _i26.Key? key;

  final String orderId;

  @override
  String toString() {
    return '{"key": "$key", "orderId": "$orderId"}';
  }

  @override
  bool operator ==(covariant PaymentViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key && other.orderId == orderId;
  }

  @override
  int get hashCode {
    return key.hashCode ^ orderId.hashCode;
  }
}

class CompletedViewArguments {
  const CompletedViewArguments({
    this.key,
    required this.orderId,
    this.unpaid = false,
    this.paid = false,
    this.photoFailed = false,
  });

  final _i26.Key? key;

  final String orderId;

  final bool unpaid;

  final bool paid;

  final bool photoFailed;

  @override
  String toString() {
    return '{"key": "$key", "orderId": "$orderId", "unpaid": "$unpaid", "paid": "$paid", "photoFailed": "$photoFailed"}';
  }

  @override
  bool operator ==(covariant CompletedViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key &&
        other.orderId == orderId &&
        other.unpaid == unpaid &&
        other.paid == paid &&
        other.photoFailed == photoFailed;
  }

  @override
  int get hashCode {
    return key.hashCode ^
        orderId.hashCode ^
        unpaid.hashCode ^
        paid.hashCode ^
        photoFailed.hashCode;
  }
}

class MyLoadViewArguments {
  const MyLoadViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant MyLoadViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class PendingCollectionsViewArguments {
  const PendingCollectionsViewArguments({this.key});

  final _i26.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant PendingCollectionsViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

extension NavigatorStateExtension on _i28.NavigationService {
  Future<dynamic> navigateToHomeView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.homeView,
      arguments: HomeViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToStartupView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.startupView,
      arguments: StartupViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToLoginView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.loginView,
      arguments: LoginViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToDirectionsView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.directionsView,
      arguments: DirectionsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToDeliveryView({
    _i26.Key? key,
    required String orderId,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.deliveryView,
      arguments: DeliveryViewArguments(key: key, orderId: orderId),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToLegalView({
    _i26.Key? key,
    required _i7.LegalDocument document,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.legalView,
      arguments: LegalViewArguments(key: key, document: document),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToWelcomeView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.welcomeView,
      arguments: WelcomeViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToForgotPasswordView({
    _i26.Key? key,
    String? email,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.forgotPasswordView,
      arguments: ForgotPasswordViewArguments(key: key, email: email),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToProfileView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.profileView,
      arguments: ProfileViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToPersonalInfoView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.personalInfoView,
      arguments: PersonalInfoViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToChangePasswordView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.changePasswordView,
      arguments: ChangePasswordViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToDeliveriesView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.deliveriesView,
      arguments: DeliveriesViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToDeliveryDetailView({
    _i26.Key? key,
    required _i27.DriverOrder order,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.deliveryDetailView,
      arguments: DeliveryDetailViewArguments(key: key, order: order),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToVehicleView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.vehicleView,
      arguments: VehicleViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToEarningsView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.earningsView,
      arguments: EarningsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToRatingView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.ratingView,
      arguments: RatingViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToNotificationsView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.notificationsView,
      arguments: NotificationsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToHelpView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.helpView,
      arguments: HelpViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToAboutView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.aboutView,
      arguments: AboutViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToDeliveryQrView({
    _i26.Key? key,
    required String orderId,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.deliveryQrView,
      arguments: DeliveryQrViewArguments(key: key, orderId: orderId),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToPaymentView({
    _i26.Key? key,
    required String orderId,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.paymentView,
      arguments: PaymentViewArguments(key: key, orderId: orderId),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToCompletedView({
    _i26.Key? key,
    required String orderId,
    bool unpaid = false,
    bool paid = false,
    bool photoFailed = false,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.completedView,
      arguments: CompletedViewArguments(
        key: key,
        orderId: orderId,
        unpaid: unpaid,
        paid: paid,
        photoFailed: photoFailed,
      ),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToMyLoadView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.myLoadView,
      arguments: MyLoadViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToPendingCollectionsView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.pendingCollectionsView,
      arguments: PendingCollectionsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithHomeView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.homeView,
      arguments: HomeViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithStartupView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.startupView,
      arguments: StartupViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithLoginView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.loginView,
      arguments: LoginViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithDirectionsView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.directionsView,
      arguments: DirectionsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithDeliveryView({
    _i26.Key? key,
    required String orderId,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.deliveryView,
      arguments: DeliveryViewArguments(key: key, orderId: orderId),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithLegalView({
    _i26.Key? key,
    required _i7.LegalDocument document,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.legalView,
      arguments: LegalViewArguments(key: key, document: document),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithWelcomeView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.welcomeView,
      arguments: WelcomeViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithForgotPasswordView({
    _i26.Key? key,
    String? email,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.forgotPasswordView,
      arguments: ForgotPasswordViewArguments(key: key, email: email),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithProfileView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.profileView,
      arguments: ProfileViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithPersonalInfoView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.personalInfoView,
      arguments: PersonalInfoViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithChangePasswordView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.changePasswordView,
      arguments: ChangePasswordViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithDeliveriesView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.deliveriesView,
      arguments: DeliveriesViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithDeliveryDetailView({
    _i26.Key? key,
    required _i27.DriverOrder order,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.deliveryDetailView,
      arguments: DeliveryDetailViewArguments(key: key, order: order),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithVehicleView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.vehicleView,
      arguments: VehicleViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithEarningsView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.earningsView,
      arguments: EarningsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithRatingView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.ratingView,
      arguments: RatingViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithNotificationsView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.notificationsView,
      arguments: NotificationsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithHelpView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.helpView,
      arguments: HelpViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithAboutView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.aboutView,
      arguments: AboutViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithDeliveryQrView({
    _i26.Key? key,
    required String orderId,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.deliveryQrView,
      arguments: DeliveryQrViewArguments(key: key, orderId: orderId),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithPaymentView({
    _i26.Key? key,
    required String orderId,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.paymentView,
      arguments: PaymentViewArguments(key: key, orderId: orderId),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithCompletedView({
    _i26.Key? key,
    required String orderId,
    bool unpaid = false,
    bool paid = false,
    bool photoFailed = false,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.completedView,
      arguments: CompletedViewArguments(
        key: key,
        orderId: orderId,
        unpaid: unpaid,
        paid: paid,
        photoFailed: photoFailed,
      ),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithMyLoadView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.myLoadView,
      arguments: MyLoadViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithPendingCollectionsView({
    _i26.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
        transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.pendingCollectionsView,
      arguments: PendingCollectionsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }
}
