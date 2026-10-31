import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';
import 'package:splg_lib/theme/app_theme.dart';

import 'helpers/test_helpers.dart';

void main() {
  setUp(() => registerServices());
  tearDown(() => locator.reset());

  testWidgets(
      'el Inicio no tiene Jornada ni Mi ubicación flotando; el estado es un chip '
      'en la hoja inferior', (tester) async {
    final ubicacion = getAndRegisterLocationService();
    when(ubicacion.checkLocationPermission()).thenAnswer((_) async => true);
    when(ubicacion.requestLocationPermission()).thenAnswer((_) async => true);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const HomeView()),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-workday')), findsNothing);
    expect(find.byKey(const Key('home-locate')), findsNothing);
    expect(find.text('Mi ubicación'), findsNothing);
    expect(find.text('Jornada'), findsNothing);

    final chip = tester.getRect(find.byKey(const Key('home-status')));
    final boton = tester.getRect(find.text('Conectarse'));
    expect(find.text('Desconectado'), findsOneWidget);
    expect(chip.bottom, lessThanOrEqualTo(boton.top),
        reason: 'el chip va sobre el botón Conectarse');
    expect(chip.height, lessThan(48), reason: 'discreto, no un bloque');
  });
}
