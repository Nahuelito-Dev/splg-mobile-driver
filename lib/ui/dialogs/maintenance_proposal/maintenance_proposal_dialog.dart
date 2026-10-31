import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';

/// Texto del aviso de propuesta nueva.
String maintenanceNoticeText(MaintenanceProposal p) =>
    'Taller para ${p.vehicleLabel}: ${p.taskName} — '
    '${formatWindow(p.windowStart, p.windowEnd)}. '
    'Respondé antes de ${formatArDay(p.expiresAt)} ${formatArTime(p.expiresAt)}.';

/// Aviso de una propuesta de taller nueva. No bloquea el reparto: se puede
/// cerrar (la propuesta queda en "Taller"). Cada botón informa su elección por
/// [onAction]; quien lo muestra decide cómo cerrarlo.
class MaintenanceProposalDialog extends StatelessWidget {
  const MaintenanceProposalDialog({
    super.key,
    required this.proposal,
    required this.onAction,
  });

  final MaintenanceProposal proposal;
  final void Function(NoticeAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final p = proposal;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Turno de taller', style: type.heading)),
                if (p.urgent)
                  const SplgStatusBadge(
                      label: 'Urgente', tone: SplgTone.danger),
              ],
            ),
            const SizedBox(height: 10),
            Text(maintenanceNoticeText(p),
                key: const Key('maintenance-notice-text'), style: type.body),
            const SizedBox(height: 18),
            SplgButton(
              key: const Key('maintenance-notice-accept'),
              title: 'Aceptar',
              onPressed: () => onAction(NoticeAction.accept),
            ),
            const SizedBox(height: 8),
            SplgButton(
              key: const Key('maintenance-notice-reject'),
              title: 'No puedo',
              style: SplgButtonStyle.outlined,
              onPressed: () => onAction(NoticeAction.reject),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                key: const Key('maintenance-notice-later'),
                onPressed: () => onAction(NoticeAction.later),
                child: const Text('Después'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
