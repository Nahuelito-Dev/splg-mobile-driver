import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';

/// Una notificación para mostrar en la lista.
class DriverNotification {
  const DriverNotification({
    required this.title,
    required this.content,
    required this.createdAt,
  });

  final String title;
  final String content;
  final DateTime createdAt;
}

/// Ruta de notificaciones. El back no expone una lista de notificaciones del
/// usuario (sólo registra el token de push), así que hoy muestra el estado
/// vacío; [NotificationsScreen] ya sabe dibujar la lista agrupada por día para
/// cuando exista el endpoint.
class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) => const NotificationsScreen();
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    this.items = const [],
    this.now,
  });

  final List<DriverNotification> items;

  /// Reloj para agrupar (Hoy / Ayer / Anteriores); por defecto el real.
  final DateTime? now;

  static String dayTitle(DateTime date, DateTime now) {
    final d = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return 'Hoy';
    if (d == today.subtract(const Duration(days: 1))) return 'Ayer';
    return 'Anteriores';
  }

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final clock = now ?? DateTime.now();
    final groups = <String, List<DriverNotification>>{};
    for (final n in [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt))) {
      groups.putIfAbsent(dayTitle(n.createdAt, clock), () => []).add(n);
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const SplgHeader(title: 'Notificaciones', onGradient: true),
      body: SplgGradientBackground(
        child: SafeArea(
          child: items.isEmpty
              ? const SplgEmptyState(
                  onDark: true,
                  imageWidth: 130,
                  illustration: SplgIllustration.emptyNotifications,
                  message: 'No tenés ninguna notificación pendiente.',
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(top: 16, bottom: 12),
                        children: [
                          for (final e in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 20),
                              child: Text(e.key,
                                  style:
                                      type.body.copyWith(color: Colors.white)),
                            ),
                            for (final n in e.value) ...[
                              ListTile(
                                title: Text(n.title,
                                    style: type.value
                                        .copyWith(color: Colors.white)),
                                subtitle: Text(n.content,
                                    style: type.caption
                                        .copyWith(color: Colors.white)),
                                trailing: const Icon(SplgIcons.next,
                                    color: Colors.white, size: 18),
                              ),
                              const Divider(
                                  color: Colors.white24,
                                  indent: 20,
                                  endIndent: 20),
                            ],
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: SplgButton(
                        title: 'Volver al inicio',
                        style: SplgButtonStyle.white,
                        onPressed: () =>
                            Navigator.of(context).popUntil((r) => r.isFirst),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
