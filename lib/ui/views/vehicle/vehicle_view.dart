import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'vehicle_viewmodel.dart';

/// Vehículo en uso, sólo lectura: la flota la carga el administrador.
class VehicleView extends StackedView<VehicleViewModel> {
  const VehicleView({super.key});

  @override
  VehicleViewModel viewModelBuilder(BuildContext context) => VehicleViewModel();

  @override
  void onViewModelReady(VehicleViewModel viewModel) => viewModel.load();

  @override
  Widget builder(BuildContext context, VehicleViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return LoadScaffold(
      title: 'Mi vehículo',
      centerTitle: false,
      model: model,
      builder: (context) {
        final v = model.vehicle;
        if (v == null) {
          return const SplgEmptyState(
            message: 'Todavía no tenés un vehículo asignado. '
                'Consultalo con tu distribuidora.',
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Registro del vehículo', style: type.subtitle),
              Divider(color: brasa.outline, height: 30),
              SplgSoftCard(
                label: '${v.brand} ${v.model}',
                amount: v.patent,
                amountKey: const Key('vehicle-patent'),
              ),
              const SizedBox(height: 20),
              SplgInfoSection(
                icon: SplgIcons.vehicle,
                title: 'Datos del vehículo',
                rows: [
                  SplgInfoRow(title: 'Patente:', value: v.patent),
                  SplgInfoRow(title: 'Marca:', value: v.brand),
                  SplgInfoRow(title: 'Modelo:', value: v.model),
                  if (v.type != null)
                    SplgInfoRow(title: 'Tipo:', value: v.type),
                  if (v.assignedAt != null)
                    SplgInfoRow(
                        title: 'Asignado el:',
                        value: formatDate(v.assignedAt!)),
                ],
              ),
              Text(
                'Los datos del vehículo los carga tu distribuidora. Si algo '
                'está mal, pedile el cambio.',
                style: type.caption,
              ),
            ],
          ),
        );
      },
    );
  }
}
