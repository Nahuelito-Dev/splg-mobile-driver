import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Utilidades de los recorridos contra el back real.
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

/// Arranca la app y deja al chofer en el Inicio, en línea y buscando pedidos.
Future<void> loginAndConnect(
    WidgetTester t, Future<void> Function() startApp) async {
  await startApp();
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
  final connect = find.text('Conectarse');
  if (connect.evaluate().isNotEmpty) {
    await tapText(t, 'Conectarse');
    await dismissPrompts(t);
  }
  await pumpUntil(t, find.text('Buscando pedidos…'));
}

/// Espera una oferta de "Cliente Prueba" (los pedidos de este recorrido) y
/// rechaza las que sean de otro cliente: el chofer de pruebas se comparte con
/// otras pruebas en curso.
Future<void> waitOwnOffer(WidgetTester t, {int seconds = 90}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 500));
    if (find.text('Datos del pedido').evaluate().isEmpty) continue;
    // Deja cargar el cliente.
    for (var i = 0;
        i < 8 && find.text('Cliente Prueba').evaluate().isEmpty;
        i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
    if (find.text('Cliente Prueba').evaluate().isNotEmpty) return;
    // ignore: avoid_print
    print('OFERTA AJENA: se rechaza');
    await t.tap(find.text('Volver'));
    await t.pump(const Duration(seconds: 2));
  }
  throw TestFailure('No llegó una oferta de Cliente Prueba');
}
