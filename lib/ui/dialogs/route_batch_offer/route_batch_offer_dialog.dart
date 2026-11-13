import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/ui/widgets/route_batch_stops.dart';

import 'route_batch_offer_dialog_model.dart';

/// Oferta de un recorrido, a pantalla completa: las paradas en orden con la
/// llegada estimada, la distancia y el peso total, y la cuenta regresiva hasta
/// que vence. «Aceptar recorrido» asigna todos los pedidos; «Rechazar» pasa el
/// lote al siguiente chofer.
///
/// `request.data` es el [RouteBatch] leído del back. El completer devuelve
/// `DialogResponse(confirmed: outcome == accepted, data: {outcome, error})`.
class RouteBatchOfferDialog extends StackedView<RouteBatchOfferDialogModel> {
  final DialogRequest request;
  final Function(DialogResponse) completer;

  const RouteBatchOfferDialog({
    super.key,
    required this.request,
    required this.completer,
  });

  RouteBatch get _batch => request.data as RouteBatch;

  void _done(RouteBatchOfferDialogModel model, BatchOutcome outcome) {
    completer(DialogResponse(
      confirmed: outcome == BatchOutcome.accepted,
      data: {
        'outcome': outcome,
        'error': model.acceptError,
      },
    ));
  }

  @override
  Widget builder(
    BuildContext context,
    RouteBatchOfferDialogModel model,
    Widget? child,
  ) {
    final type = SplgType.of(context);
    final batch = model.batch;
    final stops = model.stops;
    final km = batch.totalDistanceKm;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) model.reject();
      },
      child: Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: -MediaQueryData.fromView(View.of(context)).padding.top,
              bottom: -MediaQueryData.fromView(View.of(context)).padding.bottom,
              child: const DecoratedBox(
                key: Key('batch-screen'),
                decoration: BoxDecoration(gradient: SplgGradients.surface),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Rechazar',
                          onPressed: model.isAccepting ? null : model.reject,
                          icon: const Icon(SplgIcons.back, color: Colors.white),
                        ),
                        Expanded(
                          child: Text('Recorrido ofrecido',
                              textAlign: TextAlign.center,
                              style:
                                  type.heading.copyWith(color: Colors.white)),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 8),
                    const SizedBox(height: 10),
                    Text(
                        '${stops.length} ${stops.length == 1 ? 'parada' : 'paradas'}',
                        key: const Key('batch-stops-count'),
                        style: type.amount.copyWith(color: Colors.white)),
                    if (batch.scheduleText != null)
                      Text(batch.scheduleText!,
                          key: const Key('batch-schedule'),
                          style: type.bodyStrong.copyWith(color: Colors.white)),
                    Text(
                        [
                          kgText(batch.totalWeightKg),
                          if (km > 0) kmText(km),
                        ].join(' - '),
                        key: const Key('batch-summary'),
                        style: type.caption.copyWith(color: Colors.white70)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: RouteBatchStopList(
                        key: const Key('batch-stops'),
                        stops: stops,
                      ),
                    ),
                    if (model.acceptError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(model.acceptError!,
                            key: const Key('batch-accept-error'),
                            textAlign: TextAlign.center,
                            style: type.body.copyWith(color: Colors.white)),
                      ),
                    SplgCountdownBar(
                      remaining: model.remainingSeconds,
                      total: model.totalSeconds,
                      onDark: true,
                    ),
                    const SizedBox(height: 12),
                    SplgActionButton(
                      key: const Key('batch-accept'),
                      title: 'Aceptar recorrido',
                      loading: model.isAccepting,
                      onPressed: model.isFinished || model.isAccepting
                          ? null
                          : model.accept,
                    ),
                    const SizedBox(height: 8),
                    SplgButton(
                      key: const Key('batch-reject'),
                      title: 'Rechazar',
                      style: SplgButtonStyle.ghost,
                      onPressed: model.isFinished || model.isAccepting
                          ? null
                          : model.reject,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  RouteBatchOfferDialogModel viewModelBuilder(BuildContext context) =>
      RouteBatchOfferDialogModel(batch: _batch);

  @override
  void onViewModelReady(RouteBatchOfferDialogModel viewModel) {
    viewModel.start((outcome) => _done(viewModel, outcome));
    super.onViewModelReady(viewModel);
  }
}
