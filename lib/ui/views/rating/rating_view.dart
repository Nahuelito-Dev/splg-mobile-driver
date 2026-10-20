import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'rating_viewmodel.dart';

/// Promedio y cantidad de calificaciones. El detalle por estrella y los
/// comentarios no se muestran: el back sólo se los da a administradores.
class RatingView extends StackedView<RatingViewModel> {
  const RatingView({super.key});

  @override
  RatingViewModel viewModelBuilder(BuildContext context) => RatingViewModel();

  @override
  void onViewModelReady(RatingViewModel viewModel) => viewModel.load();

  @override
  Widget builder(BuildContext context, RatingViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return LoadScaffold(
      title: 'Tu calificación',
      model: model,
      builder: (context) {
        final s = model.summary!;
        if (s.count == 0) {
          return const SplgEmptyState(
            message: 'Todavía no tenés calificaciones. Aparecen cuando los '
                'clientes califiquen tus entregas.',
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SplgAvatar(
                        imageUrl: model.photoUrl,
                        initials: model.initials,
                        radius: 34),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.profile?.fullName ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: type.subtitle),
                        Row(
                          children: [
                            Text('${s.count} calificaciones - ',
                                style: type.caption
                                    .copyWith(color: brasa.primaryStrong)),
                            Icon(SplgIcons.star, size: 12, color: brasa.accent),
                            Text(' ${s.average.toStringAsFixed(1)}',
                                style: type.caption
                                    .copyWith(color: brasa.primaryStrong)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Divider(color: brasa.outline, height: 40),
              Row(
                children: [
                  Text(s.average.toStringAsFixed(1),
                      key: const Key('rating-average'),
                      style: type.amount.copyWith(fontSize: context.sp(30))),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SplgStarRating(rating: s.average),
                        const SizedBox(height: 4),
                        Text(
                            s.count == 1
                                ? '1 calificación'
                                : '${s.count} calificaciones',
                            style: type.bodyStrong),
                      ],
                    ),
                  ),
                ],
              ),
              Divider(color: brasa.outline, height: 30),
              Text(
                'El detalle por estrella y los comentarios todavía no están '
                'disponibles en la app.',
                style: type.caption,
              ),
            ],
          ),
        );
      },
    );
  }
}
