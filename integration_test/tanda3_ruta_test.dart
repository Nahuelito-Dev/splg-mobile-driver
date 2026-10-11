import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splg_driver/main.dart' as app;

/// Recorrido de la tanda 3 contra el back real: oferta, aceptar, en camino,
/// QR, cobro, calificar y "¡Ganaste!"; rechazar una oferta y la cancelación del
/// cliente con el chofer en camino. Un script externo crea los pedidos y
/// simula al cliente cuando ve `READY:<paso>`; saca la captura con `SHOT:<n>`.
///
///   flutter test integration_test/tanda3_test.dart -d `simulador` \
///     --dart-define=API_BASE_URL=http://localhost:3010 \
///     --dart-define=PUSH_ENABLED=false
Future<void> pumpUntil(WidgetTester t, Finder f, {int seconds = 40}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();
  // ignore: avoid_print
  print('PANTALLA: $texts');
  throw TestFailure('No apareció: $f');
}

Finder byHint(String hint) => find
    .byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint)
    .last;

Future<void> shot(WidgetTester t, String name) async {
  await t.pump(const Duration(seconds: 1));
  // ignore: avoid_print
  print('SHOT:$name');
  await t.pump(const Duration(seconds: 3));
}

void ready(String step) {
  // ignore: avoid_print
  print('READY:$step');
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text);
  await pumpUntil(t, f);
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 800));
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await pumpUntil(t, f);
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 800));
}

Future<void> dismissPrompts(WidgetTester t) async {
  final later = find.text('Ahora no');
  for (var i = 0; i < 12 && later.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 500));
  }
  if (later.evaluate().isNotEmpty) {
    await t.tap(later);
    await t.pump(const Duration(seconds: 1));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chofer: ruta por calles y vehículo en movimiento', (t) async {
    await app.main();
    final welcome = find.text('Comenzar');
    final home = find.byKey(const Key('home-menu'));
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (welcome.evaluate().isEmpty && home.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end))
        throw TestFailure('sin bienvenida ni home');
      await t.pump(const Duration(milliseconds: 250));
    }
    if (welcome.evaluate().isNotEmpty) {
      await tapText(t, 'Comenzar');
      await pumpUntil(t, find.text('Ingresar'));
      await t.enterText(byHint('Email'), 'chofer@splg.com');
      await t.enterText(byHint('Contraseña'), 'Test1234');
      await t.pump(const Duration(milliseconds: 500));
      await tapText(t, 'Ingresar');
      await pumpUntil(t, home, seconds: 40);
    }
    await dismissPrompts(t);
    await t.pump(const Duration(seconds: 3));
    await tapText(t, 'Conectarse');
    await dismissPrompts(t);
    await pumpUntil(t, find.text('Buscando pedidos…'));
    ready('create-r');
    await pumpUntil(t, find.text('Datos del pedido'), seconds: 60);
    await tapText(t, 'Aceptar pedido');
    await pumpUntil(t, find.text('Permanecer en SPLG'));
    await tapText(t, 'Permanecer en SPLG');
    await pumpUntil(t, find.byKey(const Key('trip-leave')));
    await t.pump(const Duration(seconds: 4));
    await shot(t, 'ruta-01-aceptado');
    await tapKey(t, 'trip-leave');
    await pumpUntil(t, find.byKey(const Key('trip-arrive')));
    await t.pump(const Duration(seconds: 4));
    await shot(t, 'ruta-02-en-camino-quieto');
    ready('move');
    for (var i = 3; i <= 8; i++) {
      await t.pump(const Duration(seconds: 7));
      await shot(t, 'ruta-0$i-moviendose');
    }
    // Suelta la cámara al tocar el mapa y la recentra con el botón.
    await t.tapAt(const Offset(200, 380));
    await t.pump(const Duration(seconds: 1));
    await shot(t, 'ruta-09-camara-suelta');
    await tapKey(t, 'trip-locate');
    await t.pump(const Duration(seconds: 3));
    await shot(t, 'ruta-10-recentrada');
    ready('end');
    await t.pump(const Duration(seconds: 5));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
