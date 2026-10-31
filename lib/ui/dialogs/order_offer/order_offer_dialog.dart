import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/trip_order.dart';
import 'package:splg_driver/services/navigation_launcher.dart';

import 'order_offer_dialog_model.dart';

String paymentLabel(String? method) => switch (method) {
      'cash' => 'Efectivo',
      'online' => 'Mercado Pago',
      null => 'No informado',
      final other => other,
    };

IconData paymentIcon(String? method) =>
    method == 'online' ? SplgIcons.card : SplgIcons.cash;

/// Oferta de pedido, a pantalla completa (referencia de diseño: "Datos del viaje"):
/// monto, cliente con su calificación, dirección, garrafas y forma de pago,
/// con la cuenta regresiva. "Aceptar pedido" pregunta con qué mapa seguir;
/// "Volver" rechaza.
///
/// `request.data` trae el payload del socket (`orderId`, `totalAmount`,
/// `paymentMethod`, `expiresAt`). El completer devuelve
/// `DialogResponse(confirmed: true, data: {map, lat, lng})` al aceptar y
/// `confirmed: false` si rechaza o vence. `accepted` dice si el back ya
/// confirmó la aceptación (se hace antes de elegir mapa).
class OrderOfferDialog extends StackedView<OrderOfferDialogModel> {
  final DialogRequest request;
  final Function(DialogResponse) completer;

  const OrderOfferDialog({
    super.key,
    required this.request,
    required this.completer,
  });

  Map<String, dynamic> get _data => (request.data is Map)
      ? Map<String, dynamic>.from(request.data as Map)
      : <String, dynamic>{};

  void _reject(OrderOfferDialogModel model) {
    model.stop();
    completer(DialogResponse(confirmed: false));
  }

  Future<void> _accept(
      BuildContext context, OrderOfferDialogModel model) async {
    final orderId = _data['orderId']?.toString();
    if (model.isAccepting) return;
    if (orderId == null) {
      model.missingOrder();
      return;
    }
    final order = model.order;
    // Primero se acepta en el back y se frena la cuenta: elegir el mapa puede
    // llevar un rato y no puede hacer vencer la oferta.
    final outcome = await model.acceptInBackend(orderId);
    final accepted = outcome == AcceptOutcome.accepted;
    MapApp map = MapApp.stay;
    if (accepted && order != null && order.hasCoordinates && context.mounted) {
      final picked = await showDialog<MapApp>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const SplgChoiceDialog<MapApp>(
          message:
              'Al aceptar el pedido debés elegir un tipo de mapa para continuar:',
          boldPrefix: 'aceptar',
          choices: [
            SplgChoice(MapApp.stay, 'Permanecer en SPLG', bold: true),
            SplgChoice(MapApp.google, 'Ir a Google Maps'),
            SplgChoice(MapApp.waze, 'Ir a Waze'),
          ],
        ),
      );
      map = picked ?? MapApp.stay;
    }
    completer(DialogResponse(confirmed: true, data: {
      'map': map.name,
      'lat': order?.lat,
      'lng': order?.lng,
      'accepted': accepted,
      'refused': outcome == AcceptOutcome.refused,
      'error': model.acceptError,
    }));
  }

  @override
  Widget builder(
    BuildContext context,
    OrderOfferDialogModel model,
    Widget? child,
  ) {
    final type = SplgType.of(context);
    final data = _data;
    final order = model.order;
    final total = order?.total ??
        (data['totalAmount'] is num ? data['totalAmount'] as num : null);
    final method = order?.paymentMethod ?? data['paymentMethod']?.toString();
    final rating = model.customerRating;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _reject(model);
      },
      child: Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // El diálogo respeta las zonas seguras: el degradé se extiende
            // hasta los bordes reales de la pantalla.
            Positioned(
              left: 0,
              right: 0,
              top: -MediaQueryData.fromView(View.of(context)).padding.top,
              bottom: -MediaQueryData.fromView(View.of(context)).padding.bottom,
              child: const DecoratedBox(
                key: Key('offer-screen'),
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
                          tooltip: 'Volver',
                          onPressed: () => _reject(model),
                          icon: const Icon(SplgIcons.back, color: Colors.white),
                        ),
                        Expanded(
                          child: Text('Datos del pedido',
                              textAlign: TextAlign.center,
                              style:
                                  type.heading.copyWith(color: Colors.white)),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            Text(
                                total == null
                                    ? 'Monto no disponible'
                                    : formatMoney(total),
                                key: const Key('offer-total'),
                                style:
                                    type.amount.copyWith(color: Colors.white)),
                            Text('Método de pago: ${paymentLabel(method)}',
                                style: type.caption
                                    .copyWith(color: Colors.white70)),
                            const SizedBox(height: 14),
                            _body(context, model, order, rating),
                          ],
                        ),
                      ),
                    ),
                    if (model.acceptError != null && _data['orderId'] == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(model.acceptError!,
                            key: const Key('offer-accept-error'),
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
                      title: 'Aceptar pedido',
                      onPressed: model.isFinished || model.isAccepting
                          ? null
                          : () => _accept(context, model),
                    ),
                    const SizedBox(height: 8),
                    SplgButton(
                      title: 'Volver',
                      style: SplgButtonStyle.ghost,
                      onPressed: model.isFinished ? null : () => _reject(model),
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

  Widget _body(BuildContext context, OrderOfferDialogModel model,
      TripOrder? order, RatingSummary? rating) {
    final type = SplgType.of(context);
    if (model.loading && order == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (order == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          model.loadError ?? 'No pudimos cargar los datos del pedido.',
          key: const Key('offer-load-error'),
          textAlign: TextAlign.center,
          style: type.body.copyWith(color: Colors.white),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SplgPartyRow(
          name: order.customerName ?? 'Cliente',
          initials: _initials(order.customerName),
          rating: rating?.average,
          ratingCount: rating?.count,
          onDark: true,
          avatarRadius: 28,
        ),
        const SizedBox(height: 16),
        SplgRouteRow(
          icon: SplgIcons.location,
          text: order.address ?? 'Dirección no disponible',
          caption:
              order.windowText == null ? null : 'Franja ${order.windowText}',
          onDark: true,
        ),
        const SizedBox(height: 12),
        SplgRouteRow(
          icon: SplgIcons.flame,
          text: order.lines.isEmpty ? 'Sin detalle' : order.linesText,
          caption: 'Garrafas',
          color: Colors.white24,
          onDark: true,
        ),
        const SizedBox(height: 12),
        SplgRouteRow(
          icon: paymentIcon(order.paymentMethod),
          text: paymentLabel(order.paymentMethod),
          caption: order.isCash
              ? 'Cobrás al entregar'
              : 'Lo paga el cliente por la app',
          color: Colors.white24,
          onDark: true,
        ),
        if (order.notes != null || order.instructions != null) ...[
          const SizedBox(height: 12),
          SplgRouteRow(
            icon: SplgIcons.notes,
            text: [order.instructions, order.notes]
                .whereType<String>()
                .join(' - '),
            caption: 'Indicaciones',
            color: Colors.white24,
            onDark: true,
          ),
        ],
      ],
    );
  }

  static String? _initials(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final parts = name.trim().split(RegExp(r'\s+'));
    final a = parts.first[0];
    final b = parts.length > 1 ? parts.last[0] : '';
    return (a + b).toUpperCase();
  }

  @override
  OrderOfferDialogModel viewModelBuilder(BuildContext context) =>
      OrderOfferDialogModel();

  @override
  void onViewModelReady(OrderOfferDialogModel viewModel) {
    final data = _data;
    // Al vencer, se descarta la oferta como un rechazo (el backend ya la
    // re-ofreció a otro chofer). Mismo camino que tocar "Volver".
    viewModel.start(
      data['expiresAt'],
      () => completer(DialogResponse(confirmed: false)),
    );
    final id = data['orderId']?.toString();
    if (id != null) viewModel.load(id);
    super.onViewModelReady(viewModel);
  }
}
