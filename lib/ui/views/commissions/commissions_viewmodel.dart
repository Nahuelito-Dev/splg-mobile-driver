import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

/// Mis comisiones (CU-244): lo ganado por entrega en el período, con lo
/// pendiente de liquidar y lo ya liquidado.
class CommissionsViewModel extends LoadViewModel {
  final _ops = locator<DriverOpsRepository>();

  /// Reloj inyectable para los tests.
  DateTime Function() now = DateTime.now;

  MyCommissions data = const MyCommissions();

  /// 0 este mes, 1 mes anterior, 2 últimos 7 días.
  int period = 0;

  (DateTime, DateTime) get range {
    final n = now();
    return switch (period) {
      1 => (DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 0)),
      2 => (n.subtract(const Duration(days: 6)), n),
      _ => (DateTime(n.year, n.month, 1), n),
    };
  }

  Future<void> selectPeriod(int value) {
    period = value;
    return load();
  }

  @override
  Future<void> fetch() async {
    final (from, to) = range;
    data = await _ops.myCommissions(from, to);
  }
}
