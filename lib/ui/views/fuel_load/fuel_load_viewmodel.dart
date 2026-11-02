import 'dart:async';

import 'package:dio/dio.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/ui/common/amount_input.dart';
import 'package:splg_driver/ui/common/send_intent.dart';

/// Cargar combustible (CU-195): siempre en el vehículo que el chofer tiene en
/// uso. El total (litros × precio por litro) lo calcula el back: la pantalla lo
/// pide cuando el chofer deja de teclear y manda ese mismo importe al registrar.
class FuelLoadViewModel extends BaseViewModel {
  FuelLoadViewModel({this.quoteDebounce = const Duration(milliseconds: 400)});

  final Duration quoteDebounce;
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

  /// El importe que calculó el back para los litros y el precio de hoy; null
  /// mientras no llegó o si no se pudo calcular.
  num? total;

  /// No se pudo pedir el importe al back (sin red, 5xx): se explica y se
  /// reintenta al tocar los litros o el precio.
  bool quoteFailed = false;

  /// El back rechazó la cotización (400): se muestra su mensaje tal cual.
  String? quoteRejection;

  Timer? _quoteTimer;
  int _quoteRun = 0;

  /// Pide el importe al back cuando el chofer deja de teclear. Una respuesta
  /// lenta de un valor viejo no pisa a la del valor actual.
  void _scheduleQuote() {
    _quoteTimer?.cancel();
    final run = ++_quoteRun;
    total = null;
    quoteFailed = false;
    quoteRejection = null;
    final l = litersValue, p = unitPriceValue;
    if (l == null || p == null || l <= 0 || p <= 0) return;
    _quoteTimer = Timer(quoteDebounce, () async {
      num? result;
      String? rejection;
      try {
        result = await _ops.quoteFuelLoad(liters: l, unitPrice: p);
      } catch (e) {
        result = null;
        final status = e is DioException ? e.response?.statusCode : null;
        if (status == 400 || status == 422) rejection = actionErrorText(e);
      }
      if (run != _quoteRun) return;
      total = result;
      quoteRejection = rejection;
      quoteFailed = result == null && rejection == null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    super.dispose();
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
    if (quoteRejection != null) return quoteRejection;
    if (quoteFailed) {
      return 'No pudimos calcular el total. Revisá la conexión y volvé a tocar los litros o el precio.';
    }
    if (total == null) return 'Calculando el total…';
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
    // Sin red se reintenta con cualquier cambio; un rechazo del back, sólo si
    // cambian los litros o el precio.
    if (liters != null || unitPrice != null || quoteFailed) _scheduleQuote();
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
