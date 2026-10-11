import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';
import 'package:splg_driver/ui/views/login/login_view.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import '../helpers/test_helpers.dart';
import '../helpers/test_helpers.mocks.dart';

void main() {
  late MockNavigationService nav;

  setUp(() {
    registerServices();
    nav = locator<NavigationService>() as MockNavigationService;
  });
  tearDown(() => locator.reset());

  Future<void> pumpLogin(WidgetTester t) async {
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const LoginView()));
    await t.pump();
  }

  testWidgets('la flecha atrás lleva a la Bienvenida sin usar pop', (t) async {
    await pumpLogin(t);
    await t.tap(find.byKey(const Key('login-back')));
    await t.pump();
    verify(nav.clearStackAndShow(Routes.welcomeView)).called(1);
  });

  testWidgets('el botón atrás del sistema también vuelve a la Bienvenida',
      (t) async {
    await pumpLogin(t);
    await t.binding.handlePopRoute();
    await t.pump();
    verify(nav.clearStackAndShow(Routes.welcomeView)).called(1);
  });
}
