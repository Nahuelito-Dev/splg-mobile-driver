import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:jennygas_lib/theme/app_theme.dart';

import 'package:driver_mobile/app/app.router.dart';
import 'package:driver_mobile/app/app.dialogs.dart';
import 'package:driver_mobile/app/app.locator.dart';
import 'package:driver_mobile/firebase_options.dart';
import 'package:driver_mobile/app/app.bottomsheets.dart';
import 'package:driver_mobile/services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Handler de mensajes FCM con la app en background/terminated. Tiene que
  // registrarse antes de cualquier otra cosa (ver fcm_service.dart).
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await setupLocator();
  setupDialogUi();
  setupBottomSheetUi();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: Routes.startupView,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      onGenerateRoute: StackedRouter().onGenerateRoute,
      navigatorKey: StackedService.navigatorKey,
      navigatorObservers: [StackedService.routeObserver],
    );
  }
}
