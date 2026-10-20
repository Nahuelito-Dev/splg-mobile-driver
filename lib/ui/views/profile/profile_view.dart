import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'profile_viewmodel.dart';

class ProfileView extends StackedView<ProfileViewModel> {
  const ProfileView({super.key});

  @override
  ProfileViewModel viewModelBuilder(BuildContext context) => ProfileViewModel();

  @override
  void onViewModelReady(ProfileViewModel viewModel) => viewModel.load();

  @override
  Widget builder(BuildContext context, ProfileViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return LoadScaffold(
      title: 'Mi perfil',
      model: model,
      builder: (context) {
        final p = model.profile!;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SplgAvatar(
                          imageUrl: model.photoUrl,
                          initials: model.initials,
                          radius: 40),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.fullName,
                              style: type.subtitle.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                          if (p.phone != null)
                            Text(p.phone!,
                                style: type.bodyStrong.copyWith(
                                    fontWeight: FontWeight.w400,
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: brasa.outline, height: 16),
              SplgMenuItem(
                label: 'Información personal',
                selected: model.selected == 0,
                icon: SplgIcons.user,
                onTap: model.openPersonalInfo,
              ),
              SplgMenuItem(
                label: 'Mi vehículo',
                selected: model.selected == 1,
                icon: SplgIcons.vehicle,
                onTap: model.openVehicle,
              ),
              SplgMenuItem(
                label: 'Cambiar contraseña',
                selected: model.selected == 2,
                icon: SplgIcons.key,
                onTap: model.openChangePassword,
              ),
              Divider(color: brasa.outline, height: 30),
            ],
          ),
        );
      },
    );
  }
}
