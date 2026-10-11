import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

class ProfileViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();
  final _nav = locator<NavigationService>();

  DriverProfile? profile;

  /// Fila tocada (queda resaltada, como en el perfil de la referencia).
  int? selected;

  void _select(int i) {
    selected = i;
    notifyListeners();
  }

  /// URL firmada de la foto en S3; null si no cargó ninguna.
  String? photoUrl;

  @override
  Future<void> fetch() async {
    profile = await _api.profile(refresh: true);
    // La foto es opcional: si falla, se muestran las iniciales.
    try {
      photoUrl = await _api.photoUrl();
    } catch (_) {
      photoUrl = null;
    }
  }

  String get initials {
    final parts = (profile?.fullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  Future<void> openPersonalInfo() {
    _select(0);
    return _nav.navigateToPersonalInfoView();
  }

  Future<void> openVehicle() {
    _select(1);
    return _nav.navigateToVehicleView();
  }

  Future<void> openChangePassword() {
    _select(2);
    return _nav.navigateToChangePasswordView();
  }
}
