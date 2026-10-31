import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/ui/widgets/labeled_field.dart';
import 'reject_proposal_viewmodel.dart';

/// Abre "No puedo". Devuelve la propuesta ya resuelta, o null si se cerró sin
/// responder. La hoja se cierra por su propia ruta, no "la de arriba": mientras
/// está abierta puede aparecer otra cosa encima (una oferta de pedido).
Future<MaintenanceProposal?> showRejectProposalSheet(
  BuildContext context,
  MaintenanceProposal proposal,
  MaintenanceSettings? settings, [
  DateTime Function()? now,
]) async {
  final out = ValueNotifier<MaintenanceProposal?>(null);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => RejectProposalSheet(
        proposal: proposal, settings: settings, now: now, out: out),
  );
  final done = out.value;
  out.dispose();
  return done;
}

/// Cierra la ruta que contiene [context] (la de la hoja), esté donde esté en
/// la pila.
void closeOwnRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route != null && route.isActive) {
    Navigator.of(context).removeRoute(route);
  }
}

class RejectProposalSheet extends StackedView<RejectProposalViewModel> {
  const RejectProposalSheet({
    super.key,
    required this.proposal,
    required this.settings,
    required this.out,
    this.now,
  });

  final MaintenanceProposal proposal;
  final MaintenanceSettings? settings;
  final DateTime Function()? now;

  /// Acá deja la hoja la propuesta resuelta antes de cerrarse.
  final ValueNotifier<MaintenanceProposal?> out;

  @override
  RejectProposalViewModel viewModelBuilder(BuildContext context) =>
      RejectProposalViewModel(proposal: proposal, settings: settings, now: now);

  @override
  void onViewModelReady(RejectProposalViewModel viewModel) => viewModel.init();

  Future<void> _pickTime(BuildContext context, int? initial,
      void Function(int) set, int fallback) async {
    final base = initial ?? fallback;
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: base ~/ 60, minute: base % 60));
    if (t != null) set(t.hour * 60 + t.minute);
  }

  Future<void> _pickDay(BuildContext context, RejectProposalViewModel m) async {
    final bounds = m.dayBounds;
    if (bounds == null) return;
    final (first, last, initial) = bounds;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      selectableDayPredicate: (d) =>
          m.isSelectableDay(DateTime.utc(d.year, d.month, d.day)),
      helpText: 'Día del taller',
    );
    if (picked != null) m.setDay(picked);
  }

  String _hhmm(int? m) => m == null
      ? 'Elegir'
      : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget builder(
      BuildContext context, RejectProposalViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final s = model.settings;
    if (model.closedByBack) {
      // La propuesta se cerró con la hoja abierta: se cierra sola.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => closeOwnRoute(context));
    }
    final altError = model.alternativeError;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No puedo ese día', style: type.heading),
              const SizedBox(height: 4),
              Text(
                  '${proposal.vehicleLabel} · ${formatWindow(proposal.windowStart, proposal.windowEnd)}',
                  style: type.caption),
              const SizedBox(height: 14),
              LabeledField(
                key: const Key('reject-reason'),
                label: 'Motivo',
                hint: 'Ej.: ese día tengo turno médico',
                maxLength: RejectProposalViewModel.maxReason,
                lines: 3,
                enabled: !model.isBusy,
                onChanged: model.setReason,
              ),
              SplgCheckboxLink(
                key: const Key('reject-alt-toggle'),
                label: 'Quiero proponer otra ventana',
                value: model.wantsAlternative,
                onChanged:
                    model.canPropose ? model.setWantsAlternative : (_) {},
              ),
              if (model.cannotProposeReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(model.cannotProposeReason!,
                      key: const Key('reject-cannot-propose'),
                      style: type.caption),
                ),
              if (model.wantsAlternative && s != null) ...[
                const SizedBox(height: 12),
                Text('El taller atiende: ${s.scheduleText}.',
                    style: type.caption),
                const SizedBox(height: 8),
                SplgButton(
                  key: const Key('reject-alt-day'),
                  title: model.day == null
                      ? 'Elegir el día'
                      : formatLongDate(model.day!),
                  style: SplgButtonStyle.outlined,
                  onPressed:
                      model.isBusy ? null : () => _pickDay(context, model),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SplgButton(
                        key: const Key('reject-alt-start'),
                        title: 'Desde ${_hhmm(model.startMinutes)}',
                        style: SplgButtonStyle.outlined,
                        onPressed: model.isBusy
                            ? null
                            : () => _pickTime(context, model.startMinutes,
                                model.setStart, s.workshopStartHour * 60),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SplgButton(
                        key: const Key('reject-alt-end'),
                        title: 'Hasta ${_hhmm(model.endMinutes)}',
                        style: SplgButtonStyle.outlined,
                        onPressed: model.isBusy
                            ? null
                            : () => _pickTime(context, model.endMinutes,
                                model.setEnd, s.workshopEndHour * 60),
                      ),
                    ),
                  ],
                ),
                if (altError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(altError,
                        key: const Key('reject-alt-error'),
                        style:
                            type.caption.copyWith(color: context.brasa.danger)),
                  ),
              ],
              const SizedBox(height: 16),
              if (model.failure != null) ActionError(model.failure!),
              SplgButton(
                key: const Key('reject-submit'),
                title: 'Enviar',
                loading: model.isBusy,
                onPressed: model.canSubmit
                    ? () async {
                        await model.submit();
                        if (model.result != null && context.mounted) {
                          out.value = model.result;
                          closeOwnRoute(context);
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
