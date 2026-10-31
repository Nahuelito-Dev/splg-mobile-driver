import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/ui/widgets/labeled_field.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'reject_proposal_sheet.dart';
import 'taller_viewmodel.dart';

/// `3 h 12 min` / `12 min 05 s` / `42 s`.
String formatLeft(int seconds) {
  if (seconds >= 3600) {
    return '${seconds ~/ 3600} h ${(seconds % 3600) ~/ 60} min';
  }
  if (seconds >= 60) {
    return '${seconds ~/ 60} min ${(seconds % 60).toString().padLeft(2, '0')} s';
  }
  return '$seconds s';
}

/// "Taller": propuesta vigente, a la espera del administrador, confirmada e
/// historial.
class TallerView extends StackedView<TallerViewModel> {
  const TallerView({super.key, this.clock});

  /// Reloj de la pantalla; sólo los tests lo fijan.
  final DateTime Function()? clock;

  @override
  TallerViewModel viewModelBuilder(BuildContext context) =>
      TallerViewModel(now: clock);

  @override
  void onViewModelReady(TallerViewModel viewModel) {
    viewModel.init();
    viewModel.load();
  }

  @override
  Widget builder(BuildContext context, TallerViewModel model, Widget? child) {
    final type = SplgType.of(context);
    return LoadScaffold(
      title: 'Taller',
      centerTitle: false,
      model: model,
      builder: (context) {
        final open = model.open;
        return RefreshIndicator(
          onRefresh: model.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: [
              if (model.notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(model.notice!,
                      key: const Key('taller-notice'), style: type.body),
                ),
              if (model.isEmpty)
                const SizedBox(
                  height: 360,
                  child: SplgEmptyState(
                    illustration: SplgIllustration.calendar,
                    title: 'Sin turnos de taller',
                    message: 'Cuando tu vehículo necesite pasar por el taller, '
                        'te proponemos una fecha acá.',
                  ),
                ),
              if (open.isNotEmpty) ...[
                _Heading(open.length == 1
                    ? 'Para responder'
                    : 'Para responder (${open.length})'),
                for (final cur in open)
                  _ProposalCard(
                    key: Key('taller-open-${cur.proposalId}'),
                    proposal: cur,
                    urgent: model.isUrgent(cur),
                    footer: _Actions(model: model, proposal: cur),
                    extra: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Respondé antes de ${formatArDay(cur.expiresAt)} '
                        '${formatArTime(cur.expiresAt)} · vence en '
                        '${formatLeft(model.secondsLeft(cur))}',
                        key: Key('taller-countdown-${cur.proposalId}'),
                        style: type.caption,
                      ),
                    ),
                  ),
              ],
              if (model.confirmed.isNotEmpty) ...[
                _Heading('Confirmado'),
                for (final w in model.confirmed)
                  SplgSoftCard(
                    label: '${w.vehicleLabel} · ${w.taskName}',
                    amount: formatArDay(w.start),
                    caption: 'De ${formatArTime(w.start)} a '
                        '${formatArTime(w.end)}. El despacho no te ofrece '
                        'pedidos en ese horario.',
                  ),
              ],
              if (model.waiting.isNotEmpty) ...[
                _Heading('Esperando al administrador'),
                for (final p in model.waiting)
                  _ProposalCard(
                    proposal: p,
                    badge: p.hasAlternative
                        ? const SplgStatusBadge(
                            label: 'Propusiste otra ventana',
                            tone: SplgTone.info)
                        : const SplgStatusBadge(
                            label: 'Aceptada', tone: SplgTone.success),
                    windowStart: p.hasAlternative ? p.altWindowStart : null,
                    windowEnd: p.hasAlternative ? p.altWindowEnd : null,
                  ),
              ],
              if (model.history.isNotEmpty) ...[
                _Heading('Historial'),
                for (final p in model.history)
                  _ProposalCard(
                    proposal: p,
                    badge: SplgStatusBadge(
                        label: model.statusLabel(p), tone: _tone(p, model)),
                  ),
              ],
              if (model.failure != null &&
                  (open.isEmpty || model.failedProposalId == null))
                ActionError(model.failure!),
              if (model.settings != null && !model.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                      'Horario del taller: ${model.settings!.scheduleText}.',
                      style: type.caption),
                ),
            ],
          ),
        );
      },
    );
  }

  SplgTone _tone(MaintenanceProposal p, TallerViewModel m) =>
      switch (p.status) {
        ProposalStatus.accepted => SplgTone.success,
        ProposalStatus.rejected => SplgTone.neutral,
        _ => SplgTone.warn,
      };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Text(text, style: SplgType.of(context).subtitle),
      );
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    super.key,
    required this.proposal,
    this.badge,
    this.extra,
    this.footer,
    this.windowStart,
    this.windowEnd,
    this.urgent = false,
  });

  final MaintenanceProposal proposal;
  final Widget? badge;
  final Widget? extra;
  final Widget? footer;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final p = proposal;
    final start = windowStart ?? p.windowStart;
    final end = windowEnd ?? p.windowEnd;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.brasa.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${p.vehicleLabel} · ${p.taskName}',
                    style: type.subtitle),
              ),
              if (urgent)
                const SplgStatusBadge(label: 'Urgente', tone: SplgTone.danger)
              else if (badge != null)
                badge!,
            ],
          ),
          const SizedBox(height: 8),
          Text(formatWindow(start, end), style: type.body),
          if (p.status == ProposalStatus.rejected && p.rejectionReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child:
                  Text('Tu motivo: ${p.rejectionReason}', style: type.caption),
            ),
          if (extra != null) extra!,
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.model, required this.proposal});

  final TallerViewModel model;
  final MaintenanceProposal proposal;

  @override
  Widget build(BuildContext context) {
    final busy = model.busyProposalId == proposal.proposalId;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          if (model.failure != null &&
              model.failedProposalId == proposal.proposalId)
            ActionError(model.failure!),
          SplgButton(
            key: Key('taller-accept-${proposal.proposalId}'),
            title: 'Aceptar',
            loading: busy,
            onPressed: busy ? null : () => model.accept(proposal),
          ),
          const SizedBox(height: 8),
          SplgButton(
            key: Key('taller-reject-${proposal.proposalId}'),
            title: 'No puedo',
            style: SplgButtonStyle.outlined,
            onPressed: busy
                ? null
                : () async {
                    final done = await showRejectProposalSheet(
                        context, proposal, model.settings, model.now);
                    if (done != null) model.onRejected(done);
                  },
          ),
        ],
      ),
    );
  }
}
