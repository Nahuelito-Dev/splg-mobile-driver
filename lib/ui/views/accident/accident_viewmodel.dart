import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/services/location_service.dart';
import 'package:splg_driver/ui/common/send_intent.dart';

/// Reportar un siniestro (CU-201) del vehículo en uso. Ocurre "ahora" y, si
/// hay GPS, con el punto donde está el chofer.
class AccidentViewModel extends BaseViewModel {
  final _ops = locator<DriverOpsRepository>();

  /// Reloj inyectable para los tests.
  DateTime Function() now = DateTime.now;

  String description = '';
  String address = '';
  String policeReport = '';
  bool injuries = false;
  bool thirdParties = false;
  bool hazmatRelease = false;
  bool vehicleUnusable = false;

  String? failure;
  AccidentRecord? result;
  final _intent = SendIntent<AccidentInput>();

  String? get blocker =>
      description.trim().isEmpty ? 'Contanos qué pasó.' : null;

  bool get canSubmit => !isBusy && blocker == null;

  void change({String? description, String? address, String? policeReport}) {
    this.description = description ?? this.description;
    this.address = address ?? this.address;
    this.policeReport = policeReport ?? this.policeReport;
    _intent.reset();
    failure = null;
    notifyListeners();
  }

  void setFlag({
    bool? injuries,
    bool? thirdParties,
    bool? hazmatRelease,
    bool? vehicleUnusable,
  }) {
    this.injuries = injuries ?? this.injuries;
    this.thirdParties = thirdParties ?? this.thirdParties;
    this.hazmatRelease = hazmatRelease ?? this.hazmatRelease;
    this.vehicleUnusable = vehicleUnusable ?? this.vehicleUnusable;
    _intent.reset();
    notifyListeners();
  }

  String? _location() {
    final p = locator<LocationService>().currentPosition;
    return p == null ? null : '${p.latitude},${p.longitude}';
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    failure = null;
    setBusy(true);
    try {
      // La hora, el punto y la clave se fijan en el primer intento: un
      // reintento tras un corte reenvía el mismo siniestro, no uno nuevo.
      final input = _intent.payload(() => AccidentInput(
            occurredAt: now(),
            description: description,
            address: address,
            location: _location(),
            injuries: injuries,
            thirdPartiesInvolved: thirdParties,
            hazmatRelease: hazmatRelease,
            vehicleUnusable: vehicleUnusable,
            policeReportNumber: policeReport,
          ));
      result = await _ops.reportAccident(input, idempotencyKey: _intent.key);
      _intent.reset();
    } catch (e) {
      failure = actionErrorText(e);
      if (!keepIdempotencyKey(e)) _intent.reset();
    }
    setBusy(false);
  }
}
