import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splg_driver/main.dart' as app;
import 'package:splg_lib/splg_lib.dart';

/// Ubicación NEGADA en la app chofer (se rechaza la explicación previa, o el
/// permiso está denegado): la app sigue funcionando, explica qué pasa y ofrece
/// Ajustes. Requiere el permiso sin otorgar:
///
///   xcrun simctl privacy `udid` revoke location com.nahuelwagner.splg.driver
///   flutter test integration_test/permisos_test.dart -d `simulador` \
///     --dart-define=API_BASE_URL=http://localhost:3010 --dart-define=PUSH_ENABLED=false
///
/// Usa chofer@splg.com / Test1234 (inicia y cierra sesión).
Future<void> pumpUntil(WidgetTester t, Finder f, {int seconds = 30}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('No apareció: $f');
}

Future<void> shot(WidgetTester t, String name) async {
  // ignore: avoid_print
  print('SHOT:$name');
  await t.pump(const Duration(seconds: 3));
}

Finder byHint(String hint) => find
    .byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    )
    .last;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chofer: con la ubicación denegada la app explica y sigue',
      (t) async {
    await app.main();

    // Si quedó una sesión, el flujo igual llega al inicio; si no, login.
    final continuar = find.text('Ingresar');
    final avisoAjustes = find.text('Permisos de ubicación requeridos');
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (continuar.evaluate().isEmpty && avisoAjustes.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('sin login ni aviso');
      }
      // Aviso previo (ubicación denegada para siempre): se descarta.
      final ahoraNo = find.text('Ahora no');
      if (ahoraNo.evaluate().isNotEmpty) {
        await shot(t, '20-aviso-ajustes');
        await t.tap(ahoraNo);
      }
      await t.pump(const Duration(milliseconds: 250));
    }
    if (continuar.evaluate().isNotEmpty) {
      await t.enterText(byHint('Email'), 'chofer@splg.com');
      await t.enterText(byHint('Contraseña'), 'Test1234');
      await t.tap(continuar);
    }

    // Home: primero el aviso con camino a Ajustes (se descarta con "Ahora no").
    final end2 = DateTime.now().add(const Duration(seconds: 40));
    while (avisoAjustes.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end2)) {
        throw TestFailure('sin estado de permiso');
      }
      final ahoraNo = find.text('Ahora no');
      if (ahoraNo.evaluate().isNotEmpty) {
        await shot(t, '20-aviso-ajustes');
        await t.tap(ahoraNo);
      }
      await t.pump(const Duration(milliseconds: 250));
    }

    // La explicación previa se rechaza ("Ahora no"): se ve el estado, sin mapa.
    await t.pump(const Duration(seconds: 2));
    final explicacion = find.text('Ahora no');
    if (explicacion.evaluate().isNotEmpty) {
      await shot(t, '20-explicacion-previa');
      await t.tap(explicacion);
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('Solicitar permisos'), findsOneWidget);
    expect(find.text('Abrir configuración'), findsOneWidget);
    expect(find.text('Conectarse'), findsNothing);
    await shot(t, '21-estado-sin-ubicacion');

    // Sin reintentos en bucle: pasa el tiempo y no vuelve a aparecer ningún aviso.
    await t.pump(const Duration(seconds: 10));
    expect(find.text('Ahora no'), findsNothing,
        reason: 'no vuelve a pedir ni a avisar sola');

    // La app sigue usable: menú y cierre de sesión.
    t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await t.pump(const Duration(seconds: 1));
    await shot(t, '21b-menu');
    await pumpUntil(t, find.text('Términos y condiciones'));
    await t.tap(find.text('Términos y condiciones'));
    await pumpUntil(t, find.textContaining('Términos y Condiciones de Uso'));
    await shot(t, '21c-terminos');
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pump(const Duration(seconds: 2));
    t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await t.pump(const Duration(seconds: 1));
    await shot(t, '21d-menu-cerrar');
    await pumpUntil(t, find.text('Cerrar sesión'));
    await t.tap(find.text('Cerrar sesión'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.widgetWithText(SplgButton, 'Cerrar sesión').last);
    await t.pump(const Duration(seconds: 2));
    await shot(t, '21e-despues-cerrar');
    await pumpUntil(t, continuar);
    await shot(t, '22-sesion-cerrada');
  });
}
