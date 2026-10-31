import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';
import 'mi_carga_test.dart' show enterHome;

/// "Taller" (CU-105) contra el back real: el chofer en línea abre la pantalla
/// desde el menú y ve sus propuestas de ventana de taller. Sólo lectura: las
/// propuestas las genera el administrador (`.../maintenance-planner/run`).
///
///   flutter test integration_test/taller_test.dart -d `simulador` \
///     --dart-define=API_BASE_URL=http://localhost:3000 \
///     --dart-define=PUSH_ENABLED=false
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chofer: menú → Taller con datos reales', (t) async {
    await enterHome(t);
    await tapKey(t, 'home-menu');
    await tapText(t, 'Taller');
    await pumpUntil(t, find.text('Taller'), seconds: 20);
    // Con propuestas reales hay patente y tarea; sin ellas, el estado vacío.
    final loaded = DateTime.now().add(const Duration(seconds: 20));
    while (find.textContaining('AF218KT').evaluate().isEmpty &&
        find.text('Sin turnos de taller').evaluate().isEmpty) {
      if (DateTime.now().isAfter(loaded)) throw TestFailure('Taller no cargó');
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('No pudimos cargar'), findsNothing);
    // Ramón tiene una aceptada con el caso confirmado: sale de la API, sin socket.
    await pumpUntil(t, find.text('Confirmado'), seconds: 10);
    expect(find.textContaining('no te ofrece pedidos'), findsWidgets);
    await shot(t, 'taller');
    await t.pump(const Duration(seconds: 12));
  });
}
