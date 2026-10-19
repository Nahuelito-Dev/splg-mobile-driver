import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/ui/widgets/driver_header.dart';
import 'package:splg_driver/ui/widgets/labeled_field.dart';
import 'accident_viewmodel.dart';

/// "Reportar siniestro" del vehículo en uso.
class AccidentView extends StackedView<AccidentViewModel> {
  const AccidentView({super.key});

  @override
  AccidentViewModel viewModelBuilder(BuildContext context) =>
      AccidentViewModel();

  @override
  Widget builder(BuildContext context, AccidentViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    final r = model.result;
    if (r != null) {
      return Scaffold(
        appBar: const DriverHeader(title: 'Siniestro', centerTitle: false),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Expanded(
                  child: SplgEmptyState(
                    illustration: SplgIllustration.success,
                    title: 'Siniestro reportado',
                    message: [
                      if (r.hazmatRelease || r.assignmentKept)
                        'Avisamos a los administradores.',
                      if (r.vehicleUnusable && !r.assignmentKept)
                        'Tu vehículo quedó fuera de servicio.',
                    ].join('\n'),
                  ),
                ),
                if (r.assignmentKept)
                  Container(
                    key: const Key('accident-kept'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: brasa.warnSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Tu vehículo quedó fuera de servicio; como tenés un '
                      'pedido en curso o una carga abierta, completalo o '
                      'pedí que lo reasignen.',
                      style: type.bodyStrong.copyWith(color: brasa.ink2),
                    ),
                  ),
                SplgButton(
                    title: 'Volver', onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
      );
    }
    Widget flag(String label, bool value, ValueChanged<bool> on, Key key) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SplgCheckboxLink(
              key: key, label: label, value: value, onChanged: on),
        );
    return Scaffold(
      appBar:
          const DriverHeader(title: 'Reportar siniestro', centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            LabeledField(
              key: const Key('accident-description'),
              label: 'Qué pasó',
              hint: 'Contá qué ocurrió',
              enabled: !model.isBusy,
              maxLength: 2000,
              onChanged: (v) => model.change(description: v),
            ),
            LabeledField(
              label: 'Dónde (calle, ruta, km)',
              hint: 'Ej.: Ruta 12 km 1340',
              enabled: !model.isBusy,
              maxLength: 300,
              onChanged: (v) => model.change(address: v),
            ),
            flag(
                'Hubo heridos',
                model.injuries,
                (v) => model.setFlag(injuries: v),
                const Key('accident-injuries')),
            flag(
                'Hay terceros involucrados',
                model.thirdParties,
                (v) => model.setFlag(thirdParties: v),
                const Key('accident-third')),
            flag(
                'Hubo fuga o derrame de gas',
                model.hazmatRelease,
                (v) => model.setFlag(hazmatRelease: v),
                const Key('accident-hazmat')),
            flag(
                'El vehículo quedó inutilizable',
                model.vehicleUnusable,
                (v) => model.setFlag(vehicleUnusable: v),
                const Key('accident-unusable')),
            const SizedBox(height: 4),
            LabeledField(
              label: 'N.º de denuncia policial (opcional)',
              hint: 'Si ya hiciste la denuncia',
              enabled: !model.isBusy,
              maxLength: 40,
              onChanged: (v) => model.change(policeReport: v),
            ),
            if (model.failure != null) ActionError(model.failure!),
            SplgButton(
              key: const Key('accident-submit'),
              title: 'Reportar siniestro',
              loading: model.isBusy,
              onPressed: model.canSubmit ? model.submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
