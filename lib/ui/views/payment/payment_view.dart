import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/photo_picker.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog.dart'
    show paymentIcon, paymentLabel;

import 'package:splg_driver/ui/views/delivery_code/offer_band.dart';

import 'payment_viewmodel.dart';

/// Cobro: método de pago, total a cobrar y detalle del pedido.
class PaymentView extends StackedView<PaymentViewModel> {
  final String orderId;
  const PaymentView({super.key, required this.orderId});

  @visibleForTesting
  static PaymentViewModel Function(String)? debugViewModelFactory;

  /// Sólo para tests: reemplaza la cámara y la galería.
  @visibleForTesting
  static PhotoPicker? debugPhotoPicker;

  @override
  Widget builder(BuildContext context, PaymentViewModel model, Widget? child) {
    final type = SplgType.of(context);
    final order = model.order;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SplgGradientBackground(
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: model.isBusy
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                      : order == null
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                      model.loadError ??
                                          'No pudimos cargar el cobro.',
                                      key: const Key('payment-error'),
                                      textAlign: TextAlign.center,
                                      style: type.body
                                          .copyWith(color: Colors.white)),
                                  const SizedBox(height: 20),
                                  SplgButton(
                                      title: 'Reintentar',
                                      style: SplgButtonStyle.white,
                                      onPressed: model.load),
                                  const SizedBox(height: 8),
                                  SplgButton(
                                      key: const Key('payment-later'),
                                      title: 'Más tarde',
                                      style: SplgButtonStyle.ghost,
                                      onPressed: () => _later(context, model)),
                                ],
                              ),
                            )
                          // Con la banda de una oferta abajo puede faltar alto:
                          // el cobro se desplaza en vez de desbordar.
                          : LayoutBuilder(
                              builder: (context, box) => SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(minHeight: box.maxHeight),
                                  child: IntrinsicHeight(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 16, 20, 16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Datos del cliente',
                                              style: type.title.copyWith(
                                                  color: Colors.white)),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Icon(
                                                  paymentIcon(
                                                      order.paymentMethod),
                                                  color: Colors.white,
                                                  size: 22),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                    'Método de pago: ${paymentLabel(order.paymentMethod)}',
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                    style: type.subtitle
                                                        .copyWith(
                                                            color:
                                                                Colors.white)),
                                              ),
                                            ],
                                          ),
                                          const Divider(
                                              color: Colors.white24,
                                              height: 20),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 16),
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                    model.isCash
                                                        ? 'Total a cobrar'
                                                        : 'Total del pedido',
                                                    style: type.body.copyWith(
                                                        color: Colors.white70)),
                                                Text(
                                                    formatMoney(
                                                        order.amountToCollect),
                                                    key: const Key(
                                                        'payment-total'),
                                                    style: type.amount.copyWith(
                                                        color: Colors.white)),
                                                if (order.hasPaidDeposit)
                                                  Text(
                                                      'Total del pedido ${formatMoney(order.total)} - seña ya paga ${formatMoney(order.depositAmount)}',
                                                      key: const Key(
                                                          'payment-deposit'),
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: type.caption
                                                          .copyWith(
                                                              color: Colors
                                                                  .white70)),
                                                if (!model.isCash)
                                                  Text(model.onlineStatus,
                                                      key: const Key(
                                                          'payment-online-status'),
                                                      style: type.body.copyWith(
                                                          color: Colors.white)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Text('Detalle del pedido',
                                              style: type.subtitle.copyWith(
                                                  color: Colors.white)),
                                          const SizedBox(height: 10),
                                          SplgPartyRow(
                                            name:
                                                order.customerName ?? 'Cliente',
                                            subtitle: order.customerPhone,
                                            onDark: true,
                                            avatarRadius: 20,
                                            rating: null,
                                          ),
                                          const SizedBox(height: 10),
                                          SplgRouteRow(
                                            icon: SplgIcons.location,
                                            text: order.address ??
                                                'Dirección no disponible',
                                            onDark: true,
                                          ),
                                          const SizedBox(height: 10),
                                          SplgRouteRow(
                                            icon: SplgIcons.flame,
                                            text: order.lines.isEmpty
                                                ? 'Sin detalle'
                                                : order.linesText,
                                            color: Colors.white24,
                                            onDark: true,
                                          ),
                                          const Spacer(),
                                          if (model.actionError != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Text(model.actionError!,
                                                  key: const Key(
                                                      'payment-action-error'),
                                                  textAlign: TextAlign.center,
                                                  style: type.body.copyWith(
                                                      color: Colors.white)),
                                            ),
                                          SplgButton(
                                            key: const Key('payment-confirm'),
                                            title: model.confirmLabel,
                                            style: SplgButtonStyle.white,
                                            loading: model.submitting,
                                            onPressed: model.confirm,
                                          ),
                                          if (model.needsCashConfirmation) ...[
                                            const SizedBox(height: 8),
                                            SplgButton(
                                              key: const Key('payment-unpaid'),
                                              title: 'El cliente no pagó',
                                              style: SplgButtonStyle.ghost,
                                              onPressed: model.submitting
                                                  ? null
                                                  : () =>
                                                      _unpaid(context, model),
                                            ),
                                          ],
                                          if (!model.submitting) ...[
                                            const SizedBox(height: 8),
                                            SplgButton(
                                              key: const Key('payment-later'),
                                              title: 'Más tarde',
                                              style: SplgButtonStyle.ghost,
                                              onPressed: () =>
                                                  _later(context, model),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Text(model.footerText,
                                              key: const Key('payment-footer'),
                                              textAlign: TextAlign.center,
                                              style: type.caption.copyWith(
                                                  color: Colors.white70)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
      ),
    );
  }

  /// Sale sin registrar nada y avisa dónde queda el cobro.
  void _later(BuildContext context, PaymentViewModel model) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Cobro pendiente: lo encontrás en "Cobros pendientes" '
            'del menú.'),
      ));
    model.later();
  }

  /// Confirmación de "El cliente no pagó" con una nota opcional.
  Future<void> _unpaid(BuildContext context, PaymentViewModel model) async {
    final input = await showModalBottomSheet<UnpaidInput?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UnpaidSheet(picker: PaymentView.debugPhotoPicker),
    );
    if (input == null) return; // canceló
    await model.reportUnpaid(note: input.note, photo: input.photo);
  }

  @override
  PaymentViewModel viewModelBuilder(BuildContext context) =>
      debugViewModelFactory?.call(orderId) ??
      PaymentViewModel(orderId: orderId);

  @override
  void onViewModelReady(PaymentViewModel viewModel) {
    viewModel.hostOffers();
    viewModel.load();
    super.onViewModelReady(viewModel);
  }
}

/// Lo que carga el chofer en la hoja de "El cliente no pagó".
class UnpaidInput {
  const UnpaidInput({this.note, this.photo});
  final String? note;
  final Uint8List? photo;
}

/// Hoja "¿El cliente no pagó?": nota y foto opcionales y confirmación. Devuelve
/// lo cargado o null si se cancela.
class UnpaidSheet extends StatefulWidget {
  const UnpaidSheet({super.key, this.picker});

  /// Sólo para tests; por defecto, la cámara y la galería.
  final PhotoPicker? picker;

  @override
  State<UnpaidSheet> createState() => _UnpaidSheetState();
}

class _UnpaidSheetState extends State<UnpaidSheet> {
  final _controller = TextEditingController();
  Uint8List? _photo;
  String? _photoError;

  PhotoPicker get _picker => widget.picker ?? ImagePickerPhotoPicker();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick(PhotoSource source) async {
    try {
      final bytes = await _picker.pick(source);
      if (bytes == null || !mounted) return;
      setState(() {
        _photo = bytes;
        _photoError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => _photoError = 'No pudimos usar esa foto. Probá con otra.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SplgBottomPanel(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿El cliente no pagó?', style: type.heading),
              const SizedBox(height: 6),
              Text(
                  'Vamos a marcar el pedido como impago y avisar a la distribuidora. Podés contar qué pasó y adjuntar una foto.',
                  style: type.body),
              const SizedBox(height: 12),
              SplgTextArea(
                controller: _controller,
                hint: 'Nota (opcional)',
                maxLength: 500,
                minLines: 3,
              ),
              const SizedBox(height: 10),
              if (_photo != null)
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_photo!,
                          key: const Key('unpaid-photo'),
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Foto adjunta', style: type.body)),
                    TextButton(
                      key: const Key('unpaid-photo-remove'),
                      onPressed: () => setState(() => _photo = null),
                      child: const Text('Quitar'),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: SplgButton(
                        key: const Key('unpaid-camera'),
                        title: 'Sacar foto',
                        style: SplgButtonStyle.outlined,
                        onPressed: () => _pick(PhotoSource.camera),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SplgButton(
                        key: const Key('unpaid-gallery'),
                        title: 'Galería',
                        style: SplgButtonStyle.outlined,
                        onPressed: () => _pick(PhotoSource.gallery),
                      ),
                    ),
                  ],
                ),
              if (_photoError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_photoError!,
                      key: const Key('unpaid-photo-error'),
                      style:
                          type.caption.copyWith(color: context.brasa.danger)),
                ),
              const SizedBox(height: 12),
              SplgButton(
                key: const Key('unpaid-confirm'),
                title: 'Confirmar',
                style: SplgButtonStyle.danger,
                onPressed: () => Navigator.of(context).pop(
                    UnpaidInput(note: _controller.text.trim(), photo: _photo)),
              ),
              const SizedBox(height: 8),
              SplgButton(
                key: const Key('unpaid-cancel'),
                title: 'Cancelar',
                style: SplgButtonStyle.outlined,
                onPressed: () => Navigator.of(context).pop(null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
