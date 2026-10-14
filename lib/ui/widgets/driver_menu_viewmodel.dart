import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/ui/views/legal/legal_view.dart';

/// Navegación del menú lateral: cada ítem abre su pantalla.
class DriverMenuViewModel extends BaseViewModel {
  final _nav = locator<NavigationService>();

  Future<void> openProfile() => _nav.navigateToProfileView();
  Future<void> openDeliveries() => _nav.navigateToDeliveriesView();
  Future<void> openPendingCollections() =>
      _nav.navigateToPendingCollectionsView();
  Future<void> openMyLoad() => _nav.navigateToMyLoadView();
  Future<void> openEarnings() => _nav.navigateToEarningsView();
  Future<void> openRating() => _nav.navigateToRatingView();
  Future<void> openNotifications() => _nav.navigateToNotificationsView();
  Future<void> openHelp() => _nav.navigateToHelpView();
  Future<void> openTerms() =>
      _nav.navigateToLegalView(document: LegalDocument.terms);
  Future<void> openPrivacy() =>
      _nav.navigateToLegalView(document: LegalDocument.privacy);
  Future<void> openAbout() => _nav.navigateToAboutView();
}
