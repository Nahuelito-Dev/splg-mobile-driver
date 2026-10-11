import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splg_driver/main.dart' as app;

import 'helpers.dart';

/// Revisión H2B, parte 1: deja al chofer en camino con un pedido y avisa para
/// que el script mate la app y la vuelva a abrir (la parte 2 la mira el script).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chofer: revisión H2B (antes de matar la app)', (t) async {
    await loginAndConnect(t, app.main);
    ready('create-1');
    await waitOwnOffer(t);
    await tapText(t, 'Aceptar pedido');
    await pumpUntil(t, find.text('Permanecer en SPLG'));
    await tapText(t, 'Permanecer en SPLG');
    await tapKey(t, 'trip-leave');
    await pumpUntil(t, find.byKey(const Key('trip-arrive')));
    await shot(t, 'rev-08-en-camino-antes-de-matar');
    ready('kill');
    await t.pump(const Duration(seconds: 120));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
