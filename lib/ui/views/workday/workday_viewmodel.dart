import 'package:dio/dio.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

/// Mi jornada (CU-190, CU-315). El estado sale del back
/// (`GET /attendance/mine/current`), no de la memoria de la app. Una jornada
/// abierta de un día anterior no se cierra desde acá (el back responde 409):
/// se corrige desde el panel.
class WorkdayViewModel extends LoadViewModel {
  final _ops = locator<DriverOpsRepository>();

  /// Reloj inyectable para los tests.
  DateTime Function() now = DateTime.now;

  String? failure;

  /// Jornada que el chofer cerró en esta sesión (para avisar antes de abrir
  /// otra el mismo día).
  Workday? closedToday;

  Workday? get workday => _ops.workday;
  bool get isOpen => workday?.isOpen ?? false;

  /// Abierta de un día anterior: sin botones, a corregir desde el panel.
  bool get isStale => isOpen && workday!.isFromPastDay(now());

  bool get canStart => !isOpen && !isBusy;
  bool get canFinish => isOpen && !isStale && !isBusy;

  /// Ya cerró una jornada hoy: iniciar otra pide confirmación.
  bool get needsRestartConfirmation =>
      closedToday != null && !closedToday!.isFromPastDay(now());

  @override
  Future<void> fetch() async {
    await _ops.currentWorkday();
  }

  Future<void> start() async {
    await _mark(_ops.checkIn);
  }

  Future<void> finish() async {
    await _mark(_ops.checkOut);
  }

  Future<void> _mark(Future<Workday> Function() action) async {
    if (isBusy) return;
    failure = null;
    setBusy(true);
    try {
      final w = await action();
      if (!w.isOpen) closedToday = w;
    } catch (e) {
      failure = actionErrorText(e);
      // 409: el estado real es otro (p. ej. ya había una abierta): se relee.
      if (e is DioException && e.response?.statusCode == 409) {
        try {
          await _ops.currentWorkday();
          if (isOpen && _isAlreadyOpenMessage(failure)) failure = null;
        } catch (_) {}
      }
    }
    setBusy(false);
  }

  /// El 409 del check-in con una jornada ya abierta no es un error para el
  /// chofer: la pantalla pasa a mostrar esa jornada.
  bool _isAlreadyOpenMessage(String? m) =>
      (m ?? '').toLowerCase().contains('jornada abierta');
}
