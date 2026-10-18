import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/ui/common/amount_input.dart';
import 'package:splg_driver/ui/common/send_intent.dart';

/// Cargar combustible (CU-195): siempre en el vehículo que el chofer tiene en
/// uso. El total es litros × precio por litro (el back tolera un 1 %).
class FuelLoadViewModel extends BaseViewModel {
  final _ops = locator<DriverOpsRepository>();

  String liters = '';
  String unitPrice = '';
  String odometer = '';
  String station = '';
  String receipt = '';
  String notes = '';
  bool fullTank = true;
  FuelPayment payment = FuelPayment.driverCash;

  String? failure;
  FuelLoadRecord? result;
  final _intent = SendIntent<FuelLoadInput>();

  /// Litros con hasta 2 decimales (como el back).
  num? get litersValue => parseAmount(liters, maxDecimals: 2);

  /// Precio por litro con hasta 3 decimales (como el back).
  num? get unitPriceValue => parseAmount(unitPrice, maxDecimals: 3);
  int? get odometerValue {
    final v = parseAmount(odometer, maxDecimals: 0);
    return (v == null || v != v.truncate()) ? null : v.toInt();
  }

  num? get total {
    final l = litersValue, p = unitPriceValue;
    if (l == null || p == null) return null;
    return num.parse((l * p).toStringAsFixed(2));
  }

  String? get blocker {
    final l = litersValue, p = unitPriceValue;
    if (l == null || l <= 0) {
      return 'Ingresá los litros (hasta 2 decimales, con coma: 40,5).';
    }
    if (p == null || p <= 0) {
      return 'Ingresá el precio por litro (hasta 3 decimales, con coma).';
    }
    if (odometerValue == null || odometerValue! < 0) {
      return 'Ingresá el kilometraje del tablero (sin decimales).';
    }
    return null;
  }

  bool get canSubmit => !isBusy && blocker == null;

  void change({
    String? liters,
    String? unitPrice,
    String? odometer,
    String? station,
    String? receipt,
    String? notes,
  }) {
    this.liters = liters ?? this.liters;
    this.unitPrice = unitPrice ?? this.unitPrice;
    this.odometer = odometer ?? this.odometer;
    this.station = station ?? this.station;
    this.receipt = receipt ?? this.receipt;
    this.notes = notes ?? this.notes;
    _intent.reset();
    failure = null;
    notifyListeners();
  }

  void setFullTank(bool v) {
    fullTank = v;
    _intent.reset();
    notifyListeners();
  }

  void setPayment(FuelPayment p) {
    payment = p;
    _intent.reset();
    notifyListeners();
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    failure = null;
    setBusy(true);
    try {
      final input = _intent.payload(() => FuelLoadInput(
            liters: litersValue!,
            unitPrice: unitPriceValue!,
            totalAmount: total!,
            odometerKm: odometerValue!,
            paymentMethod: payment,
            isFullTank: fullTank,
            station: station,
            receiptNumber: receipt,
            notes: notes,
          ));
      result = await _ops.registerFuelLoad(input, idempotencyKey: _intent.key);
      _intent.reset();
    } catch (e) {
      failure = actionErrorText(e);
      if (!keepIdempotencyKey(e)) _intent.reset();
    }
    setBusy(false);
  }
}
