import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';

import 'delivery_qr_viewmodel.dart';

/// "Finalización": QR grande para que el cliente lo escanee.
class DeliveryQrView extends StackedView<DeliveryQrViewModel> {
  final String orderId;
  const DeliveryQrView({super.key, required this.orderId});

  @visibleForTesting
  static DeliveryQrViewModel Function(String)? debugViewModelFactory;

  @override
  Widget builder(
      BuildContext context, DeliveryQrViewModel model, Widget? child) {
    final type = SplgType.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SplgGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Volver',
                      icon: const Icon(SplgIcons.back, color: Colors.white),
                      onPressed: model.back,
                    ),
                    Expanded(
                      child: Text('Finalización',
                          textAlign: TextAlign.center,
                          style: type.heading.copyWith(color: Colors.white)),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Expanded(
                child: model.isBusy
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white))
                    : model.code == null
                        ? _Error(model: model)
                        : _Qr(model: model),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  DeliveryQrViewModel viewModelBuilder(BuildContext context) =>
      debugViewModelFactory?.call(orderId) ??
      DeliveryQrViewModel(orderId: orderId);

  @override
  void onViewModelReady(DeliveryQrViewModel viewModel) {
    viewModel.initialize();
    super.onViewModelReady(viewModel);
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.model});
  final DeliveryQrViewModel model;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(model.loadError ?? 'No pudimos cargar el código.',
                key: const Key('qr-error'),
                textAlign: TextAlign.center,
                style: SplgType.of(context).body.copyWith(color: Colors.white)),
            const SizedBox(height: 20),
            SplgButton(
                title: 'Reintentar',
                style: SplgButtonStyle.white,
                onPressed: model.load),
          ],
        ),
      );
}

class _Qr extends StatelessWidget {
  const _Qr({required this.model});
  final DeliveryQrViewModel model;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final order = model.order;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        children: [
          Text('Mostrale este QR al cliente',
              textAlign: TextAlign.center,
              style: type.heading.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text(
              'Que lo escanee con su app para confirmar que recibió las garrafas.',
              textAlign: TextAlign.center,
              style: type.body.copyWith(color: Colors.white)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: QrImageView(
              key: const Key('qr-code'),
              data: model.code!,
              size: context.sp(190),
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Text('Si no puede escanear, dictale este código:',
              textAlign: TextAlign.center,
              style: type.body.copyWith(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(model.displayCode!,
              key: const Key('qr-code-text'),
              style: type.title.copyWith(
                  color: Colors.white,
                  letterSpacing: 6,
                  fontSize: 36,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          if (order != null)
            Text(
                '${order.customerName ?? 'Cliente'} - ${formatMoney(order.total)}',
                style: type.body.copyWith(color: Colors.white70)),
          const SizedBox(height: 16),
          _Regenerate(model: model),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
              const SizedBox(width: 10),
              Text('Esperando la confirmación del cliente…',
                  key: const Key('qr-waiting'),
                  style: type.body.copyWith(color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }
}

/// «Generar código nuevo»: cuando el cliente agotó los intentos (o el código se
/// filtró). Pide confirmación porque el código anterior deja de valer.
class _Regenerate extends StatelessWidget {
  const _Regenerate({required this.model});
  final DeliveryQrViewModel model;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    if (!model.confirmingRegenerate) {
      return SplgButton(
        key: const Key('qr-regenerate'),
        title: 'Generar código nuevo',
        style: SplgButtonStyle.ghost,
        onPressed: model.askRegenerate,
      );
    }
    return Column(
      children: [
        Text(
            '¿Generar un código nuevo? El actual deja de valer y el cliente '
            'tiene que usar el nuevo.',
            key: const Key('qr-regenerate-ask'),
            textAlign: TextAlign.center,
            style: type.body.copyWith(color: Colors.white)),
        if (model.regenerateError != null) ...[
          const SizedBox(height: 8),
          Text(model.regenerateError!,
              key: const Key('qr-regenerate-error'),
              textAlign: TextAlign.center,
              style: type.body.copyWith(color: Colors.white)),
        ],
        const SizedBox(height: 10),
        SplgButton(
          key: const Key('qr-regenerate-confirm'),
          title: 'Sí, generar código nuevo',
          style: SplgButtonStyle.white,
          loading: model.regenerating,
          onPressed: model.regenerateCode,
        ),
        const SizedBox(height: 8),
        SplgButton(
          key: const Key('qr-regenerate-cancel'),
          title: 'Cancelar',
          style: SplgButtonStyle.ghost,
          onPressed: model.regenerating ? null : model.cancelRegenerate,
        ),
      ],
    );
  }
}
