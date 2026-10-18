import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'driver_menu_viewmodel.dart';

/// Menú lateral del chofer: pantalla completa sobre el degradé de marca, con
/// las entradas agrupadas por línea. Cada ítem cierra el menú y navega.
class DriverMenuDrawer extends StackedView<DriverMenuViewModel> {
  const DriverMenuDrawer({
    super.key,
    required this.onLogout,
  });

  final VoidCallback onLogout;

  @override
  DriverMenuViewModel viewModelBuilder(BuildContext context) =>
      DriverMenuViewModel();

  @override
  Widget builder(
      BuildContext context, DriverMenuViewModel model, Widget? child) {
    Widget item(String label, IconData icon, Future<void> Function() go) =>
        SplgMenuItem(
          dark: true,
          label: label,
          icon: icon,
          onTap: () {
            Navigator.of(context).pop();
            go();
          },
        );

    Widget line() => const Divider(
        indent: 15,
        endIndent: 15,
        thickness: 2,
        height: 20,
        color: Colors.white70);

    return Drawer(
      width: MediaQuery.of(context).size.width,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
      ),
      backgroundColor: Colors.transparent,
      child: SplgGradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Cerrar menú',
                      icon: const Icon(SplgIcons.back,
                          size: 24, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text('Menú',
                        style: SplgType.of(context).heading.copyWith(
                            color: Colors.white, fontSize: context.sp(14))),
                    IconButton(
                      tooltip: 'Notificaciones',
                      icon: const Icon(SplgIcons.bell,
                          size: 24, color: Colors.white),
                      onPressed: () {
                        Navigator.of(context).pop();
                        model.openNotifications();
                      },
                    ),
                  ],
                ),
                line(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      item('Mi perfil', SplgIcons.user, model.openProfile),
                      item('Mis entregas', SplgIcons.deliveries,
                          model.openDeliveries),
                      item('Mi carga', SplgIcons.truck, model.openMyLoad),
                      item('Cobros pendientes', SplgIcons.cash,
                          model.openPendingCollections),
                    ],
                  ),
                ),
                line(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      item('Mi jornada', SplgIcons.clock, model.openWorkday),
                      item('Mi rendición', SplgIcons.invoice,
                          model.openSettlement),
                      item('Mis comisiones', SplgIcons.cash,
                          model.openCommissions),
                      item('Cargar combustible', SplgIcons.flame,
                          model.openFuelLoad),
                      item('Reportar siniestro', SplgIcons.error,
                          model.openAccident),
                    ],
                  ),
                ),
                line(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      item('Estadísticas', SplgIcons.chart, model.openEarnings),
                      item('Tu calificación', SplgIcons.star, model.openRating),
                    ],
                  ),
                ),
                line(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      item('Ayuda', SplgIcons.help, model.openHelp),
                      item('Términos y condiciones', SplgIcons.terms,
                          model.openTerms),
                      item('Políticas de privacidad', SplgIcons.privacy,
                          model.openPrivacy),
                      item('Acerca de SPLG', SplgIcons.about, model.openAbout),
                    ],
                  ),
                ),
                line(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SplgMenuItem(
                    dark: true,
                    destructive: true,
                    label: 'Cerrar sesión',
                    icon: SplgIcons.logout,
                    onTap: () => _confirmLogout(context),
                  ),
                ),
                const Divider(
                    indent: 15,
                    endIndent: 15,
                    thickness: 2,
                    color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('¿Querés cerrar sesión?',
            textAlign: TextAlign.center,
            style: SplgType.of(ctx).heading.copyWith(fontSize: ctx.sp(12))),
        content: Text('Tus datos no se pierden al cerrar sesión.',
            textAlign: TextAlign.center, style: SplgType.of(ctx).body),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          SplgButton(
            title: 'Cerrar sesión',
            style: SplgButtonStyle.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: 8),
          SplgButton(
            title: 'Cancelar',
            style: SplgButtonStyle.outlined,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      onLogout();
    }
  }
}
