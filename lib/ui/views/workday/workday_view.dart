import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/labeled_field.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'workday_viewmodel.dart';

/// "Mi jornada": estado real de la jornada, iniciar y finalizar con la hora
/// del servidor.
class WorkdayView extends StackedView<WorkdayViewModel> {
  const WorkdayView({super.key});

  @override
  WorkdayViewModel viewModelBuilder(BuildContext context) => WorkdayViewModel();

  @override
  void onViewModelReady(WorkdayViewModel viewModel) => viewModel.load();

  @override
  Widget builder(BuildContext context, WorkdayViewModel model, Widget? child) {
    final type = SplgType.of(context);
    return LoadScaffold(
      title: 'Mi jornada',
      centerTitle: false,
      model: model,
      builder: (context) {
        final (title, message) = _texts(model);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: SplgEmptyState(
                  illustration: model.closedToday != null && !model.isOpen
                      ? SplgIllustration.success
                      : SplgIllustration.emptyList,
                  title: title,
                  message: message,
                ),
              ),
              if (model.failure != null) ActionError(model.failure!),
              if (model.canStart)
                SplgButton(
                  key: const Key('workday-start'),
                  title: 'Iniciar jornada',
                  loading: model.isBusy,
                  onPressed: () => _start(context, model),
                ),
              if (model.isOpen && !model.isStale)
                SplgButton(
                  key: const Key('workday-finish'),
                  title: 'Finalizar jornada',
                  loading: model.isBusy,
                  onPressed: model.canFinish ? model.finish : null,
                ),
              const SizedBox(height: 10),
              Text(
                'Marcar la jornada no te pone en línea: eso se hace desde el '
                'Inicio.',
                textAlign: TextAlign.center,
                style: type.caption,
              ),
            ],
          ),
        );
      },
    );
  }

  (String, String) _texts(WorkdayViewModel model) {
    final w = model.workday;
    final now = model.now();
    if (w != null && w.isOpen) {
      if (model.isStale) {
        return (
          'Jornada sin cerrar',
          'Tu jornada del ${_day(w.workDate)} quedó sin cerrar: corregila '
              'desde el panel.'
        );
      }
      return (
        'Jornada iniciada',
        'Empezaste ${_when(w.checkInAt, now)} a las ${formatTime(w.checkInAt)}.'
      );
    }
    final c = model.closedToday;
    if (c != null && c.checkOutAt != null && !c.isFromPastDay(now)) {
      final mins = c.durationMinutes;
      return (
        'Jornada finalizada',
        'De ${formatTime(c.checkInAt)} a ${formatTime(c.checkOutAt!)}'
            '${mins == null ? '' : ' (${mins ~/ 60} h ${mins % 60} min)'}.'
      );
    }
    return (
      'Todavía no iniciaste',
      'Iniciá tu jornada al empezar el día y finalizala al terminar.'
    );
  }

  /// `hoy` / `ayer` / `el 15/10/2026`, según la fecha real.
  String _when(DateTime at, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    return switch (diff) {
      0 => 'hoy',
      1 => 'ayer',
      _ => 'el ${formatDate(at)}',
    };
  }

  /// `2026-10-17` -> `17/10/2026`.
  String _day(String workDate) {
    final d = DateTime.tryParse(workDate);
    return d == null ? workDate : formatDate(d);
  }

  Future<void> _start(BuildContext context, WorkdayViewModel model) async {
    if (model.needsRestartConfirmation) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Iniciar otra jornada?'),
          content: const Text(
              'Ya finalizaste una jornada hoy. ¿Querés iniciar otra?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              key: const Key('workday-restart-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Iniciar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await model.start();
  }
}
