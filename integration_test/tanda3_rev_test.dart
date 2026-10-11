import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splg_driver/main.dart' as app;

import 'helpers.dart';

/// Revisión: H1 (la oferta vence con el pop-up de mapas abierto) y H3 (el
/// cliente/admin confirma la entrega con el chofer "En camino": el Inicio no
/// retoma hasta el final del flujo y no abre ofertas encima).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chofer: revisión H1 y H3', (t) async {
    await loginAndConnect(t, app.main);

    // H1: aceptar, dejar el pop-up de mapas abierto y que la oferta venza.
    ready('create-1');
    await waitOwnOffer(t);
    await tapText(t, 'Aceptar pedido');
    await pumpUntil(t, find.text('Permanecer en SPLG'));
    await shot(t, 'rev-01-popup-abierto');
    // Vence (30 s) sin tocar nada.
    final until = DateTime.now().add(const Duration(seconds: 60));
    while (find.text('Datos del pedido').evaluate().isNotEmpty ||
        find.text('Permanecer en SPLG').evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(until))
        throw TestFailure('la oferta quedó colgada');
      await t.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Permanecer en SPLG'), findsNothing);
    expect(find.text('Datos del pedido'), findsNothing);
    await shot(t, 'rev-02-tras-vencer-con-popup');

    // Un pedido nuevo: se acepta y se sale.
    ready('create-3');
    await waitOwnOffer(t);
    await tapText(t, 'Aceptar pedido');
    await pumpUntil(t, find.text('Permanecer en SPLG'));
    await tapText(t, 'Permanecer en SPLG');
    await tapKey(t, 'trip-leave');
    await pumpUntil(t, find.byKey(const Key('trip-arrive')));
    await shot(t, 'rev-03-en-camino');

    // H3: el admin confirma la entrega mientras está "En camino".
    ready('deliver-3');
    await pumpUntil(t, find.byKey(const Key('payment-confirm')), seconds: 30);
    await shot(t, 'rev-04-cobro-por-entrega-externa');
    // Con el chofer en Cobro llega otra oferta: no debe abrirse encima.
    ready('create-2');
    await t.pump(const Duration(seconds: 14));
    expect(find.text('Datos del pedido'), findsNothing);
    expect(find.byKey(const Key('payment-confirm')), findsOneWidget);
    await shot(t, 'rev-05-cobro-sin-oferta-encima');
    await tapKey(t, 'payment-confirm');
    await pumpUntil(t, find.byKey(const Key('completed-finish')));
    await shot(t, 'rev-06-completado');
    await tapKey(t, 'completed-finish');
    await pumpUntil(t, find.byKey(const Key('earned-banner')));
    await shot(t, 'rev-07-ganaste-tras-flujo-completo');
    ready('end');
    await t.pump(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
