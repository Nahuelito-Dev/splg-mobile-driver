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
  Future<void> openWorkday() => _nav.navigateToWorkdayView();
  Future<void> openSettlement() => _nav.navigateToSettlementView();
  Future<void> openFuelLoad() => _nav.navigateToFuelLoadView();
  Future<void> openAccident() => _nav.navigateToAccidentView();
  Future<void> openTaller() => _nav.navigateToTallerView();
  Future<void> openRating() => _nav.navigateToRatingView();
  Future<void> openNotifications() => _nav.navigateToNotificationsView();
  Future<void> openHelp() => _nav.navigateToHelpView();
  Future<void> openTerms() =>
      _nav.navigateToLegalView(document: LegalDocument.terms);
  Future<void> openPrivacy() =>
      _nav.navigateToLegalView(document: LegalDocument.privacy);
  Future<void> openAbout() => _nav.navigateToAboutView();
}
