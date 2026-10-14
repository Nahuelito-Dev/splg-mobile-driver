import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splg_driver/main.dart' as app;

import 'helpers.dart';

/// Aviso de "no recibís pedidos por tu carga" y Mi carga contra el back real.
/// Sólo lectura: la carga la maneja el admin (el script que corre esto la abre
/// y la pasa a "en ruta" cuando el test avisa `READY:open` / `READY:depart` y
/// crea `GO_FILE.open` / `GO_FILE.depart`). Cada `SHOT:<nombre>` del log es
/// el momento de sacar la captura con `xcrun simctl io <udid> screenshot`.
///
///   flutter test integration_test/mi_carga_test.dart -d `simulador` \
///     --dart-define=API_BASE_URL=http://localhost:3010 \
///     --dart-define=PUSH_ENABLED=false \
///     --dart-define=GO_FILE=/ruta/al/archivo
///
/// Funciona con o sin sesión iniciada y con o sin permiso de ubicación (si el
/// permiso no está dado, acepta la explicación previa; el diálogo del sistema
/// se otorga antes con `xcrun simctl privacy `udid` grant location-always
/// com.nahuelwagner.splg.driver`).
const _goFile = String.fromEnvironment('GO_FILE');

/// Lleva a la app al Inicio venga como venga: bienvenida, login, explicación de
/// permisos o aviso de permiso requerido.
Future<void> enterHome(WidgetTester t) async {
  await app.main();
  final home = find.byKey(const Key('home-menu'));
  final end = DateTime.now().add(const Duration(seconds: 120));
  while (home.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList();
      throw TestFailure('No llegó al Inicio. Pantalla: $texts');
    }
    if (find.byKey(const Key('trip-leave')).evaluate().isNotEmpty ||
        find.byKey(const Key('trip-arrive')).evaluate().isNotEmpty) {
      // La app retomó un pedido en curso de la base: sin tocarlo, se sale de
      // su pantalla (que bloquea el botón atrás) para llegar al Inicio.
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
    } else if (find.text('Comenzar').evaluate().isNotEmpty) {
      await tapText(t, 'Comenzar');
    } else if (find
            .byWidgetPredicate(
                (w) => w is TextField && w.decoration?.hintText == 'Email')
            .evaluate()
            .isNotEmpty &&
        find.text('Ingresar').evaluate().isNotEmpty) {
      await t.enterText(byHint('Email'), 'chofer@splg.com');
      await t.enterText(byHint('Contraseña'), 'Test1234');
      await t.pump(const Duration(milliseconds: 500));
      await tapText(t, 'Ingresar');
    } else if (find.text('Continuar').evaluate().isNotEmpty) {
      // Explicación previa del permiso de ubicación.
      await t.tap(find.text('Continuar'));
    } else if (find.text('Solicitar permisos').evaluate().isNotEmpty) {
      await t.tap(find.text('Solicitar permisos'));
      await t.pump(const Duration(seconds: 3));
    }
    await t.pump(const Duration(milliseconds: 400));
  }
  // Avisos que puedan haber quedado encima (p. ej. permisos de notificación).
  await dismissPrompts(t);
  await t.pump(const Duration(seconds: 2));
}

Future<void> waitGone(WidgetTester t, Finder f, {int seconds = 60}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 500));
    if (f.evaluate().isEmpty) return;
  }
  throw TestFailure('Sigue en pantalla: $f');
}

/// Avisa `READY:<paso>` y espera a que el script cree `GO_FILE.<paso>`.
Future<void> waitFor(WidgetTester t, String step) async {
  if (_goFile.isEmpty) return;
  ready(step);
  final f = File('$_goFile.$step');
  final end = DateTime.now().add(const Duration(minutes: 3));
  while (!f.existsSync()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('sin $f');
    await t.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chofer: aviso de carga y Mi carga', (t) async {
    final notice = find.byKey(const Key('home-no-orders-notice'));
    await enterHome(t);

    // Sin carga y con D5: el back no le da pedidos y lo dice.
    await pumpUntil(t, find.text('Abrí tu carga para recibir pedidos'));
    await shot(t, 'mi-carga-01-aviso-sin-carga');

    // El script abre la carga por la API del admin.
    await waitFor(t, 'open');
    await pumpUntil(t, find.textContaining('todavía no salió'), seconds: 60);
    await shot(t, 'mi-carga-02-aviso-cargando');

    await t.tap(notice);
    await pumpUntil(t, find.byType(RefreshIndicator));
    await pumpUntil(t, find.textContaining('Carga N°'));
    await shot(t, 'mi-carga-03-mi-carga-cargando');

    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pump(const Duration(seconds: 1));

    // El script la pasa a "en ruta".
    await waitFor(t, 'depart');
    await waitGone(t, notice, seconds: 60);
    await shot(t, 'mi-carga-04-inicio-en-ruta-sin-aviso');

    await tapKey(t, 'home-menu');
    await tapText(t, 'Mi carga');
    await pumpUntil(t, find.text('En ruta'));
    await shot(t, 'mi-carga-05-mi-carga-en-ruta');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
