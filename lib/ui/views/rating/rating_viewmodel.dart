import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

class RatingViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();

  RatingSummary? summary;
  DriverProfile? profile;
  String? photoUrl;

  @override
  Future<void> fetch() async {
    summary = await _api.rating();
    // El encabezado con nombre y foto es un adorno: si falla, la calificación
    // se muestra igual.
    try {
      profile = await _api.profile();
      photoUrl = await _api.photoUrl();
    } catch (_) {}
  }

  String get initials {
    final parts = (profile?.fullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
        .toUpperCase();
  }
}
