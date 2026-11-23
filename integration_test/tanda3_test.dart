import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splg_driver/main.dart' as app;

/// Recorrido de la tanda 3 contra el back real: oferta, aceptar, en camino,
/// código de entrega, cobro, calificar y "¡Ganaste!"; rechazar una oferta y la
/// cancelación del cliente con el chofer en camino. Un script externo crea los
/// pedidos y simula al cliente cuando ve `READY:<paso>`; saca la captura con
/// `SHOT:<n>`. El código de entrega lo ve el cliente (el chofer nunca): con
/// `READY:codigo-1` el script lo lee con el token del cliente
/// (`GET /api/v3/orders/:id/delivery-code`) y escribe los 6 dígitos en el
/// archivo de `--dart-define=CODE_FILE=<ruta>`; el test lo teclea.
///
///   flutter test integration_test/tanda3_test.dart -d `simulador` \
///     --dart-define=API_BASE_URL=http://localhost:3010 \
///     --dart-define=PUSH_ENABLED=false \
///     --dart-define=CODE_FILE=/tmp/codigo-entrega.txt
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

/// Espera los 6 dígitos que el script externo deja en `CODE_FILE` y los teclea.
Future<void> typeCodeFromFile(WidgetTester t, {int seconds = 60}) async {
  const path = String.fromEnvironment('CODE_FILE');
  if (path.isEmpty) {
    throw TestFailure('Falta --dart-define=CODE_FILE=<ruta del código>');
  }
  final file = File(path);
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (file.existsSync()) {
      final code = file.readAsStringSync().trim();
      if (RegExp(r'^\d{6}$').hasMatch(code)) {
        file.deleteSync();
        for (final d in code.split('')) {
          await tapKey(t, 'code-key-$d');
        }
        return;
      }
    }
  }
  throw TestFailure('No llegó el código a $path');
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

  testWidgets('chofer: tanda 3', (t) async {
    await app.main();

    final welcome = find.text('Comenzar');
    final home = find.byKey(const Key('home-menu'));
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (welcome.evaluate().isEmpty && home.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        // ignore: avoid_print
        print(
            'PANTALLA: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}');
        throw TestFailure('sin bienvenida ni home');
      }
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
    await shot(t, '01-inicio-buscando');

    // 1. Camino completo: oferta -> aceptar -> en camino -> código -> cobro -> calificar.
    ready('create-1');
    await pumpUntil(t, find.text('Datos del pedido'), seconds: 60);
    await shot(t, '02-oferta');
    await tapText(t, 'Aceptar pedido');
    await pumpUntil(t, find.text('Permanecer en SPLG'));
    await shot(t, '03-elegir-mapa');
    await tapText(t, 'Permanecer en SPLG');
    await pumpUntil(t, find.byKey(const Key('trip-leave')));
    await shot(t, '04-pedido-aceptado');
    await tapKey(t, 'trip-leave');
    await pumpUntil(t, find.byKey(const Key('trip-arrive')));
    await shot(t, '05-en-camino');
    await tapKey(t, 'trip-navigate');
    await pumpUntil(t, find.text('Ir a Waze'));
    await shot(t, '06-navegar-popup');
    await tapText(t, 'Permanecer en SPLG');
    await tapKey(t, 'trip-arrive');
    await pumpUntil(t, find.byKey(const Key('code-keypad')));
    await shot(t, '07-codigo');
    ready('codigo-1');
    await typeCodeFromFile(t);
    await tapKey(t, 'code-submit');
    await pumpUntil(t, find.byKey(const Key('payment-confirm')), seconds: 60);
    await shot(t, '08-cobro');
    await tapKey(t, 'payment-confirm');
    await pumpUntil(t, find.byKey(const Key('completed-rate')));
    await shot(t, '09-completado');
    await tapKey(t, 'completed-rate');
    await pumpUntil(t, find.byKey(const Key('rating-submit')));
    await t.tap(find.byTooltip('5 estrellas'));
    await t.pump(const Duration(milliseconds: 500));
    await shot(t, '10-calificar');
    await tapKey(t, 'rating-submit');
    await pumpUntil(t, find.byKey(const Key('completed-thanks')));
    await shot(t, '11-gracias');
    await tapKey(t, 'completed-finish');
    await pumpUntil(t, find.byKey(const Key('earned-banner')));
    await shot(t, '12-ganaste');

    // 2. Rechazar una oferta.
    ready('create-2');
    await pumpUntil(t, find.text('Datos del pedido'), seconds: 60);
    await tapText(t, 'Volver');
    await pumpUntil(t, find.text('Buscando pedidos…'));
    await shot(t, '13-oferta-rechazada');
    ready('rejected');
    await t.pump(const Duration(seconds: 6));

    // 3. El cliente cancela con el chofer en camino.
    ready('create-3');
    await pumpUntil(t, find.text('Datos del pedido'), seconds: 60);
    await tapText(t, 'Aceptar pedido');
    await pumpUntil(t, find.text('Permanecer en SPLG'));
    await tapText(t, 'Permanecer en SPLG');
    await tapKey(t, 'trip-leave');
    await pumpUntil(t, find.byKey(const Key('trip-arrive')));
    ready('cancel-3');
    await pumpUntil(t, find.text('Pedido cancelado'), seconds: 40);
    await shot(t, '14-cancelado-por-el-cliente');
    final ok = find.text('Ok');
    final OK = find.text('OK');
    await t.tap(ok.evaluate().isNotEmpty ? ok : OK);
    await pumpUntil(t, home);
    await t.pump(const Duration(seconds: 2));
    await shot(t, '15-inicio-tras-cancelacion');
    ready('done');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
