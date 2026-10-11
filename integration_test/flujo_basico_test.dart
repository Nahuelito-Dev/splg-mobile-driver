import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splg_driver/main.dart' as app;
import 'package:splg_lib/splg_lib.dart';

/// Autenticación y navegación de la app chofer contra el back real.
///
///   flutter test integration_test/flujo_basico_test.dart -d `simulador` \
///     --dart-define=API_BASE_URL=http://localhost:3010 \
///     --dart-define=PUSH_ENABLED=false
///
/// `PUSH_ENABLED=false` es necesario en simulador: sin eso el prompt de
/// notificaciones del sistema tapa la pantalla. Requiere el permiso de
/// ubicación ya otorgado (`xcrun simctl privacy `udid` grant location-always
/// com.nahuelwagner.splg.driver`).
///
/// Efectos: usa chofer@splg.com / Test1234 (inicia y cierra sesión) y
/// Firebase manda un mail real de recuperación de contraseña a esa cuenta.
/// Usalo sólo contra una base de desarrollo.
Future<void> pumpUntil(WidgetTester t, Finder f, {int seconds = 30}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('No apareció: $f');
}

Finder byHint(String hint) => find
    .byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    )
    .last;

Future<void> shot(WidgetTester t, String name) async {
  // ignore: avoid_print
  print('SHOT:$name');
  await t.pump(const Duration(seconds: 3));
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text);
  await pumpUntil(t, f);
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chofer: login, sesión, navegación y cierre de sesión',
      (t) async {
    await app.main();

    final continuar = find.text('Ingresar');
    final drawerIcon = find.byKey(const Key('home-menu'));

    // Si quedó una sesión de una corrida anterior, se cierra desde el menú.
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (continuar.evaluate().isEmpty &&
        find.byKey(const Key('home-menu')).evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('sin login ni home');
      await t.pump(const Duration(milliseconds: 250));
    }
    Future<void> cerrarSesion() async {
      final scaffold = find.byType(Scaffold).first;
      t.state<ScaffoldState>(scaffold).openDrawer();
      await t.pump(const Duration(seconds: 1));
      await tapText(t, 'Cerrar sesión');
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.widgetWithText(SplgButton, 'Cerrar sesión').last);
      await t.pump(const Duration(seconds: 1));
    }

    if (continuar.evaluate().isEmpty) {
      // ignore: avoid_print
      print('SESION_RESTAURADA');
      await t.pump(const Duration(seconds: 5));
      await cerrarSesion();
    }
    await pumpUntil(t, continuar);
    expect(drawerIcon, findsNothing);
    await shot(t, '01-login');

    // Credenciales mal: mensaje claro y se queda en el login.
    await t.enterText(byHint('Email'), 'chofer@splg.com');
    await t.enterText(byHint('Contraseña'), 'clave-mala');
    await t.tap(continuar);
    await pumpUntil(
        t, find.text('No pudimos iniciar sesión. Revisá tus datos.'));
    await shot(t, '02-login-error');

    // Una cuenta de cliente no entra a la app del chofer.
    await t.enterText(byHint('Email'), 'cliente@splg.com');
    await t.enterText(byHint('Contraseña'), 'Test1234');
    await t.tap(continuar);
    await t.pump(const Duration(seconds: 5));
    expect(find.text('Ingresar'), findsOneWidget);

    // Recuperar contraseña.
    await t.enterText(byHint('Email'), 'chofer@splg.com');
    await t.tap(find.text('¿Olvidaste tu contraseña?'));
    await pumpUntil(t, find.text('Revisá tu correo'));
    await shot(t, '03-recuperar-contrasena');
    await tapText(t, 'Ok');

    // Login correcto: llega al inicio.
    await t.enterText(byHint('Contraseña'), 'Test1234');
    await t.tap(continuar);
    await pumpUntil(t, drawerIcon, seconds: 40);
    await t.pump(const Duration(seconds: 4));
    await shot(t, '04-home');

    // Menú: legales y volver.
    t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await t.pump(const Duration(seconds: 1));
    await shot(t, '05-menu');
    await tapText(t, 'Términos y condiciones');
    await pumpUntil(t, find.textContaining('Bienvenido'));
    await shot(t, '06-terminos');
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pump(const Duration(seconds: 2));
    t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await t.pump(const Duration(seconds: 1));
    await tapText(t, 'Políticas de privacidad');
    await pumpUntil(t, find.textContaining('Política de Privacidad'));
    await shot(t, '07-privacidad');
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pump(const Duration(seconds: 2));

    // Cerrar sesión: vuelve al login.
    await cerrarSesion();
    await pumpUntil(t, continuar);
    await shot(t, '08-sesion-cerrada');
  });
}
