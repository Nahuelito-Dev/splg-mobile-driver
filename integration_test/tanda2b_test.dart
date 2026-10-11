import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:splg_driver/main.dart' as app;
import 'package:splg_lib/splg_lib.dart';

/// Recorrido de la tanda 2b contra el back real: bienvenida, login, Inicio
/// (desconectado, buscando, sin pedidos), menú y cada pantalla. Imprime
/// `SHOT:<nombre>` para que un script externo saque la captura.
///
///   flutter test integration_test/tanda2b_test.dart -d `simulador` \
///     --dart-define=API_BASE_URL=http://localhost:3010 \
///     --dart-define=PUSH_ENABLED=false
///
/// Requiere el permiso de ubicación otorgado en el simulador. Usa
/// chofer@splg.com / Test1234 (inicia y cierra sesión, se pone en línea y se
/// desconecta). No cambia la contraseña: sólo prueba el error de la actual.
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
  await t.pump(const Duration(seconds: 2));
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
  await t.pump(const Duration(milliseconds: 800));
}

Future<void> back(WidgetTester t) async {
  await t.tap(find.byTooltip('Volver').last);
  await t.pump(const Duration(seconds: 1));
}

Future<void> dismissLocationPrompt(WidgetTester t) async {
  final later = find.text('Ahora no');
  for (var i = 0; i < 12 && later.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 500));
  }
  if (later.evaluate().isNotEmpty) {
    await t.tap(later);
    await t.pump(const Duration(seconds: 1));
  }
}

Future<void> openMenu(WidgetTester t) async {
  final button = find.byKey(const Key('home-menu'));
  if (button.evaluate().isNotEmpty) {
    await t.tap(button);
  } else {
    t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  }
  await t.pump(const Duration(seconds: 1));
}

Future<void> viaMenu(WidgetTester t, String item, String shotName,
    {Future<void> Function()? extra}) async {
  await openMenu(t);
  await tapText(t, item);
  await shot(t, shotName);
  if (extra != null) await extra();
  await back(t);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chofer: tanda 2b', (t) async {
    await app.main();

    final welcome = find.text('Comenzar');
    final home = find.byKey(const Key('home-menu'));
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (welcome.evaluate().isEmpty && home.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end))
        throw TestFailure('sin bienvenida ni home');
      await t.pump(const Duration(milliseconds: 250));
    }
    Future<void> cerrarSesion() async {
      await openMenu(t);
      await tapText(t, 'Cerrar sesión');
      await shot(t, 'confirmar-cierre');
      await t.tap(find.widgetWithText(SplgButton, 'Cerrar sesión').last);
      await t.pump(const Duration(seconds: 1));
    }

    if (welcome.evaluate().isEmpty) {
      await dismissLocationPrompt(t);
      await cerrarSesion();
      await pumpUntil(t, find.text('Ingresar'));
    } else {
      await shot(t, '01-bienvenida');
      await tapText(t, 'Comenzar');
    }

    await pumpUntil(t, find.text('Ingresar'));
    await shot(t, '02-login');
    await tapText(t, '¿Olvidaste tu contraseña?');
    await pumpUntil(t, find.text('Enviar'));
    await shot(t, '03-recuperar-contrasena');
    await back(t);

    await t.enterText(byHint('Email'), 'chofer@splg.com');
    await t.enterText(byHint('Contraseña'), 'clave-mala');
    await t.pump(const Duration(milliseconds: 300));
    await tapText(t, 'Ingresar');
    await pumpUntil(
        t, find.text('No pudimos iniciar sesión. Revisá tus datos.'));
    await shot(t, '04-login-error');
    await t.enterText(byHint('Email'), 'chofer@splg.com');
    await t.enterText(byHint('Contraseña'), 'Test1234');
    await t.pump(const Duration(milliseconds: 500));
    await tapText(t, 'Ingresar');
    await pumpUntil(t, home, seconds: 40);
    await dismissLocationPrompt(t);
    await t.pump(const Duration(seconds: 4));
    await shot(t, '05-inicio-desconectado');

    // Conectarse: buscando pedidos y, pasado el tiempo, sin pedidos.
    await tapText(t, 'Conectarse');
    // La primera vez, la app explica para qué pide notificaciones.
    final later = find.text('Ahora no');
    for (var i = 0; i < 20 && later.evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
    if (later.evaluate().isNotEmpty) {
      await shot(t, '06-explicacion-notificaciones');
      await t.tap(later);
      await t.pump(const Duration(seconds: 1));
    }
    await pumpUntil(t, find.text('Buscando pedidos…'), seconds: 30);
    await shot(t, '07-inicio-buscando');
    // Si el back ofrece un pedido de pruebas, se lo rechaza para volver a la
    // búsqueda (la oferta vuelve a aparecer si nadie la toma).
    Future<void> rechazarOfertas() async {
      final reject = find.text('Rechazar');
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(seconds: 1));
        if (reject.evaluate().isNotEmpty) {
          await t.tap(reject);
          await t.pump(const Duration(seconds: 1));
        }
      }
    }

    await rechazarOfertas();
    await pumpUntil(t, find.text('Sin pedidos disponibles'), seconds: 15);
    await shot(t, '08-inicio-sin-pedidos');
    await rechazarOfertas();
    await tapText(t, 'Desconectarse');
    await pumpUntil(t, find.text('Conectarse'));
    await shot(t, '09-inicio-desconectado-de-nuevo');

    await openMenu(t);
    await shot(t, '10-menu');
    await tapText(t, 'Mi perfil');
    await pumpUntil(t, find.text('Información personal'));
    await shot(t, '11-perfil');
    await tapText(t, 'Información personal');
    await shot(t, '12-info-personal');
    await back(t);
    await tapText(t, 'Mi vehículo');
    await shot(t, '13-vehiculo');
    await back(t);
    await tapText(t, 'Cambiar contraseña');
    await shot(t, '14-cambiar-contrasena');
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'ClaveVieja1');
    await t.enterText(fields.at(1), 'Nueva1234');
    await t.enterText(fields.at(2), 'Distinta1');
    await t.pump(const Duration(milliseconds: 500));
    await shot(t, '15-contrasena-no-coincide');
    await t.enterText(fields.at(2), 'Nueva1234');
    await t.pump(const Duration(milliseconds: 500));
    await shot(t, '16-contrasena-valida');
    await tapText(t, 'Confirmar');
    await pumpUntil(t, find.text('Contraseña incorrecta'));
    await shot(t, '17-contrasena-actual-incorrecta');
    await back(t);
    await back(t);

    await viaMenu(t, 'Mis entregas', '18-entregas', extra: () async {
      await pumpUntil(t, find.textContaining(' hs'));
      await t.tap(find.textContaining(' hs').first);
      await t.pump(const Duration(seconds: 1));
      await shot(t, '19-detalle-entrega');
      await back(t);
    });
    await viaMenu(t, 'Estadísticas', '20-estadisticas');
    await viaMenu(t, 'Tu calificación', '21-calificacion');
    await openMenu(t);
    await t.tap(find.byTooltip('Notificaciones'));
    await t.pump(const Duration(seconds: 1));
    await shot(t, '22-notificaciones');
    await back(t);
    await viaMenu(t, 'Ayuda', '23-ayuda', extra: () async {
      await tapText(t, '¿Cómo me pongo en línea?');
      await shot(t, '24-ayuda-abierta');
    });
    await viaMenu(t, 'Términos y condiciones', '25-terminos');
    await viaMenu(t, 'Políticas de privacidad', '26-privacidad');
    await viaMenu(t, 'Acerca de SPLG', '27-acerca');

    await cerrarSesion();
    await pumpUntil(t, find.text('Ingresar'), seconds: 30);
    await shot(t, '28-sesion-cerrada');
  });
}
