import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_lib/theme/app_theme.dart';
import 'package:splg_driver/ui/views/home/home_view.dart';

import '../helpers/test_helpers.dart';

void main() {
  setUp(() => registerServices());
  tearDown(() => locator.reset());

  testGoldens('HomeView - default state', (tester) async {
    await loadAppFonts();

    // Set device pixel ratio and size
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(393, 852), devicePixelRatio: 1.0),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const HomeView(),
        ),
      ),
    );

    await screenMatchesGolden(tester, 'home_view_default');
  });
}
