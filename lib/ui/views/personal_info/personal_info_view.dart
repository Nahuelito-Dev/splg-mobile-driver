import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'personal_info_viewmodel.dart';

/// Datos de la cuenta, sólo lectura: los carga y corrige la distribuidora.
class PersonalInfoView extends StackedView<PersonalInfoViewModel> {
  const PersonalInfoView({super.key});

  @override
  PersonalInfoViewModel viewModelBuilder(BuildContext context) =>
      PersonalInfoViewModel();

  @override
  void onViewModelReady(PersonalInfoViewModel viewModel) => viewModel.load();

  @override
  Widget builder(
      BuildContext context, PersonalInfoViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return LoadScaffold(
      title: 'Información personal',
      centerTitle: false,
      model: model,
      builder: (context) {
        final p = model.profile!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Registro del chofer', style: type.subtitle),
              Divider(color: brasa.outline, height: 30),
              SplgInfoSection(
                icon: SplgIcons.user,
                title: 'Datos del chofer',
                rows: [
                  SplgInfoRow(title: 'Nombre y apellido:', value: p.fullName)
                ],
              ),
              SplgInfoSection(
                icon: SplgIcons.location,
                title: 'Información de contacto',
                rows: [
                  SplgInfoRow(title: 'Número de teléfono:', value: p.phone)
                ],
              ),
              SplgInfoSection(
                icon: SplgIcons.mail,
                title: 'Información de la cuenta',
                rows: [
                  SplgInfoRow(title: 'Correo electrónico:', value: p.email)
                ],
              ),
              Text(
                'Si algún dato está mal, pedile el cambio a tu distribuidora.',
                style: type.caption,
              ),
            ],
          ),
        );
      },
    );
  }
}
