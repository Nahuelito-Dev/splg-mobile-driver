import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/ui/widgets/driver_header.dart';
import 'package:splg_driver/ui/widgets/labeled_field.dart';
import 'fuel_load_viewmodel.dart';

/// "Cargar combustible" en el vehículo en uso.
class FuelLoadView extends StackedView<FuelLoadViewModel> {
  const FuelLoadView({super.key});

  @override
  FuelLoadViewModel viewModelBuilder(BuildContext context) =>
      FuelLoadViewModel();

  @override
  Widget builder(BuildContext context, FuelLoadViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final r = model.result;
    if (r != null) {
      return Scaffold(
        appBar: const DriverHeader(title: 'Combustible', centerTitle: false),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Expanded(
                  child: SplgEmptyState(
                    illustration: SplgIllustration.success,
                    title: 'Carga registrada',
                    message: '${r.liters} L por ${formatMoney(r.totalAmount)}'
                        '${r.carPatent == null ? '' : ' en ${r.carPatent}'}.'
                        '${r.anomaly ? '\nEl consumo se apartó de lo habitual: lo revisa el administrador.' : ''}',
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
    final total = model.total;
    return Scaffold(
      appBar:
          const DriverHeader(title: 'Cargar combustible', centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            LabeledField(
              key: const Key('fuel-liters'),
              label: 'Litros cargados',
              number: true,
              enabled: !model.isBusy,
              onChanged: (v) => model.change(liters: v),
            ),
            LabeledField(
              key: const Key('fuel-price'),
              label: 'Precio por litro',
              number: true,
              enabled: !model.isBusy,
              onChanged: (v) => model.change(unitPrice: v),
            ),
            if (total != null)
              InfoRow('Total', formatMoney(total), strong: true),
            const SizedBox(height: 10),
            LabeledField(
              key: const Key('fuel-odometer'),
              label: 'Kilometraje del tablero',
              number: true,
              enabled: !model.isBusy,
              onChanged: (v) => model.change(odometer: v),
            ),
            Text('Cómo se pagó', style: type.bodyStrong),
            const SizedBox(height: 6),
            DropdownButtonFormField<FuelPayment>(
              key: const Key('fuel-payment'),
              initialValue: model.payment,
              items: [
                for (final p in FuelPayment.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (v) => v == null ? null : model.setPayment(v),
            ),
            const SizedBox(height: 14),
            SplgCheckboxLink(
              label: 'Llené el tanque',
              value: model.fullTank,
              onChanged: model.setFullTank,
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Estación (opcional)',
              maxLength: 120,
              onChanged: (v) => model.change(station: v),
            ),
            LabeledField(
              label: 'Comprobante (opcional)',
              maxLength: 40,
              onChanged: (v) => model.change(receipt: v),
            ),
            LabeledField(
              label: 'Notas (opcional)',
              maxLength: 2000,
              onChanged: (v) => model.change(notes: v),
            ),
            if (model.failure != null) ActionError(model.failure!),
            if (model.blocker != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(model.blocker!, style: type.caption),
              ),
            SplgButton(
              key: const Key('fuel-submit'),
              title: 'Registrar carga',
              loading: model.isBusy,
              onPressed: model.canSubmit ? model.submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
