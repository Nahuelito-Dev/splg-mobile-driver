import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';

import 'delivery_code_viewmodel.dart';
import 'offer_band.dart';

/// "Finalización": el chofer escribe el código de 6 dígitos que le dicta el
/// cliente.
class DeliveryCodeView extends StackedView<DeliveryCodeViewModel> {
  final String orderId;
  const DeliveryCodeView({super.key, required this.orderId});

  @visibleForTesting
  static DeliveryCodeViewModel Function(String)? debugViewModelFactory;

  @override
  Widget builder(
      BuildContext context, DeliveryCodeViewModel model, Widget? child) {
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
                    : model.loadError != null
                        ? _Error(model: model)
                        : _Entry(model: model),
              ),
              OfferSlotArea(
                offer: model.pendingOffer,
                notice: model.offerNotice,
                slot: model.offerSlot,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  DeliveryCodeViewModel viewModelBuilder(BuildContext context) =>
      debugViewModelFactory?.call(orderId) ??
      DeliveryCodeViewModel(orderId: orderId);

  @override
  void onViewModelReady(DeliveryCodeViewModel viewModel) {
    viewModel.initialize();
    super.onViewModelReady(viewModel);
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.model});
  final DeliveryCodeViewModel model;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(model.loadError ?? 'No pudimos cargar el pedido.',
                key: const Key('code-load-error'),
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

class _Entry extends StatelessWidget {
  const _Entry({required this.model});
  final DeliveryCodeViewModel model;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    final order = model.order;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        children: [
          Semantics(
            header: true,
            child: Text('Pedile el código al cliente',
                textAlign: TextAlign.center,
                style: type.heading.copyWith(color: Colors.white)),
          ),
          const SizedBox(height: 6),
          Text(
              'Lo ve en su app. Escribilo acá para confirmar que entregaste '
              'las garrafas.',
              textAlign: TextAlign.center,
              style: type.body.copyWith(color: Colors.white)),
          if (order != null) ...[
            const SizedBox(height: 10),
            Text(
                '${order.customerName ?? 'Cliente'} - ${formatMoney(order.total)}',
                style: type.body.copyWith(color: Colors.white70)),
          ],
          const SizedBox(height: 20),
          Semantics(
            container: true,
            label: model.digits.isEmpty
                ? 'Código de entrega, vacío'
                : 'Código de entrega: ${model.spokenDigits}',
            child: ExcludeSemantics(
              child: Row(
                key: const Key('code-boxes'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < kDeliveryCodeLength; i++)
                    _Box(
                      key: Key('code-box-$i'),
                      char: i < model.digits.length ? model.digits[i] : '',
                      active: i == model.digits.length && !model.blocked,
                    ),
                ],
              ),
            ),
          ),
          if (model.errorMessage != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Container(
                key: Key(model.blocked ? 'code-blocked' : 'code-error'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: brasa.danger, width: 2),
                ),
                child: Text(model.errorMessage!,
                    textAlign: TextAlign.center,
                    style: type.body.copyWith(
                        color: brasa.danger, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _Keypad(model: model),
          const SizedBox(height: 18),
          SplgButton(
            key: const Key('code-submit'),
            title: 'Confirmar entrega',
            style: SplgButtonStyle.white,
            loading: model.sending,
            onPressed: model.canSubmit ? model.submit : null,
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.char, required this.active});
  final String char;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brasa = context.brasa;
    return Container(
      width: 44,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? brasa.danger : Colors.white24,
            width: active ? 3 : 1),
      ),
      child: Text(char,
          style: SplgType.of(context).title.copyWith(
              color: Colors.black87,
              fontSize: 28,
              fontWeight: FontWeight.w900)),
    );
  }
}

/// Teclado numérico propio: 1-9, 0 y borrar, con áreas táctiles de 64 px.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.model});
  final DeliveryCodeViewModel model;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> children) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center, children: children),
        );
    Widget digit(String d) => _Key(
          key: Key('code-key-$d'),
          label: d,
          semantics: d,
          onTap: () => model.addDigit(d),
        );
    return Column(
      key: const Key('code-keypad'),
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        row([digit('4'), digit('5'), digit('6')]),
        row([digit('7'), digit('8'), digit('9')]),
        row([
          const SizedBox(width: 88),
          digit('0'),
          _Key(
            key: const Key('code-key-delete'),
            label: 'Borrar',
            semantics: 'Borrar el último dígito',
            onTap: model.deleteDigit,
          ),
        ]),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(
      {super.key,
      required this.label,
      required this.semantics,
      required this.onTap});
  final String label;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Material(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              width: 80,
              height: 64,
              child: Center(
                child: Text(label,
                    style: SplgType.of(context).title.copyWith(
                        color: Colors.white,
                        fontSize: label.length > 1 ? 16 : 28,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
