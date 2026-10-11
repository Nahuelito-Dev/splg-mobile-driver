import 'package:stacked/stacked.dart';

import 'package:splg_driver/services/driver_api_service.dart';

/// Base de las pantallas que leen datos del back: carga, error con reintento.
abstract class LoadViewModel extends BaseViewModel {
  String? loadError;

  /// Trae los datos; si lanza, la pantalla muestra el error y "Reintentar".
  Future<void> fetch();

  Future<void> load() async {
    loadError = null;
    setBusy(true);
    try {
      await fetch();
    } catch (e) {
      loadError = DriverApiService.errorMessage(e);
    }
    setBusy(false);
  }
}
