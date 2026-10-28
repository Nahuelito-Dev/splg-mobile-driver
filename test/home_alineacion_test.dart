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

  testWidgets('los botones flotantes del inicio arrancan del mismo borde',
      (tester) async {
    final ubicacion = getAndRegisterLocationService();
    when(ubicacion.checkLocationPermission()).thenAnswer((_) async => true);
    when(ubicacion.requestLocationPermission()).thenAnswer((_) async => true);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const HomeView()),
    );
    await tester.pump();

    final menu = tester.getTopLeft(find.byKey(const Key('home-menu'))).dx;
    final estado = tester.getTopLeft(find.byKey(const Key('home-status'))).dx;
    final jornada = tester.getTopLeft(find.byKey(const Key('home-workday'))).dx;

    expect(estado, menu);
    expect(jornada, menu);
  });
}
