import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/app/app.router.dart';

/// Encabezado de las pantallas del chofer: flecha, título y la campana que
/// abre las notificaciones.
class DriverHeader extends StatelessWidget implements PreferredSizeWidget {
  const DriverHeader({
    super.key,
    required this.title,
    this.bell = true,
    this.centerTitle = true,
  });

  final String title;
  final bool bell;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) => SplgHeader(
        title: title,
        centerTitle: centerTitle,
        onNotifications: bell
            ? () => locator<NavigationService>().navigateToNotificationsView()
            : null,
      );
}
