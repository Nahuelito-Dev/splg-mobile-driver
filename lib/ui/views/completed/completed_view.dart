import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'completed_viewmodel.dart';

/// "¡Pedido completado!" con el botón para calificar al cliente.
class CompletedView extends StackedView<CompletedViewModel> {
  final String orderId;

  /// Se llegó por "El cliente no pagó": se muestra el aviso.
  final bool unpaid;

  /// El back confirmó el cobro en efectivo.
  final bool paid;

  /// Se reportó impago pero la foto no se pudo subir.
  final bool photoFailed;
  const CompletedView({
    super.key,
    required this.orderId,
    this.unpaid = false,
    this.paid = false,
    this.photoFailed = false,
  });

  @visibleForTesting
  static CompletedViewModel Function(String)? debugViewModelFactory;

  @override
  Widget builder(
      BuildContext context, CompletedViewModel model, Widget? child) {
    final type = SplgType.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SplgGradientBackground(
          gradient: SplgGradients.splash,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                children: [
                  const Spacer(),
                  SplgIllustration.success.image(height: context.sp(120)),
                  const SizedBox(height: 16),
                  Text('¡Pedido completado!',
                      textAlign: TextAlign.center,
                      style: type.title.copyWith(color: Colors.white)),
                  if (unpaid) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const Key('completed-unpaid-notice'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                          photoFailed
                              ? 'Quedó registrado; la distribuidora se va a comunicar. La foto no se pudo subir.'
                              : 'Quedó registrado; la distribuidora se va a comunicar.',
                          textAlign: TextAlign.center,
                          style: type.body.copyWith(color: Colors.white)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                      'Gracias por tu entrega. Recordá calificar a tu cliente para mejorar la comunidad.',
                      textAlign: TextAlign.center,
                      style: type.body.copyWith(color: Colors.white)),
                  const Spacer(),
                  if (!model.rated)
                    SplgButton(
                      key: const Key('completed-rate'),
                      title: 'Calificar cliente',
                      style: SplgButtonStyle.white,
                      onPressed: () => _rate(context, model),
                    ),
                  if (model.rated)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('¡Gracias por calificar!',
                          key: const Key('completed-thanks'),
                          style: type.subtitle.copyWith(color: Colors.white)),
                    ),
                  const SizedBox(height: 8),
                  SplgButton(
                    key: const Key('completed-finish'),
                    title: model.rated ? 'Volver al inicio' : 'Ahora no',
                    style: model.rated
                        ? SplgButtonStyle.white
                        : SplgButtonStyle.ghost,
                    onPressed: model.finish,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rate(BuildContext context, CompletedViewModel model) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RatingSheet(model: model),
    );
    if (ok == true) model.notifyListeners();
  }

  @override
  CompletedViewModel viewModelBuilder(BuildContext context) =>
      debugViewModelFactory?.call(orderId) ??
      CompletedViewModel(orderId: orderId, paid: paid);

  @override
  void onViewModelReady(CompletedViewModel viewModel) {
    viewModel.load();
    super.onViewModelReady(viewModel);
  }
}

/// "Calificá a tu cliente": estrellas y comentario de hasta 300 caracteres.
class RatingSheet extends StatefulWidget {
  const RatingSheet({super.key, required this.model});
  final CompletedViewModel model;

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.model.comment;
    widget.model.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.model.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final type = SplgType.of(context);
    final order = m.order;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SplgBottomPanel(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Cerrar',
                  icon:
                      Icon(SplgIcons.back, color: context.brasa.primaryStrong),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                Text('Calificá a tu cliente', style: type.heading),
              ],
            ),
            SplgPartyRow(
              name: order?.customerName ?? 'Cliente',
              rating: m.customerRating?.average,
              ratingCount: m.customerRating?.count,
              avatarRadius: 20,
            ),
            const SizedBox(height: 8),
            SplgRatingInput(
                value: m.stars, onChanged: m.setStars, enabled: !m.submitting),
            SplgTextArea(
              controller: _controller,
              hint: 'Escribí una reseña o recomendación…',
              enabled: !m.submitting,
              errorText: null,
            ),
            if (m.ratingError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(m.ratingError!,
                    key: const Key('rating-error'),
                    style: type.caption.copyWith(color: context.brasa.danger)),
              ),
            const SizedBox(height: 12),
            SplgButton(
              key: const Key('rating-submit'),
              title: 'Calificar cliente',
              loading: m.submitting,
              onPressed: () async {
                m.setComment(_controller.text);
                final ok = await m.submitRating();
                if (ok && context.mounted) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
    );
  }
}
