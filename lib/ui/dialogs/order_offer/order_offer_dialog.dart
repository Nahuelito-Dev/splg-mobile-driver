import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:driver_mobile/ui/common/app_colors.dart';
import 'package:driver_mobile/ui/common/ui_helpers.dart';

import 'order_offer_dialog_model.dart';

final _currencyFormat =
    NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);

/// Dialog que se muestra cuando llega una oferta de pedido nueva mientras el
/// chofer está conectado (evento de socket `server:new-order-request`).
///
/// `request.data` trae el payload crudo del evento:
/// `{ orderId, totalAmount, paymentMethod, expiresAt, items }`. El completer
/// devuelve `DialogResponse(confirmed: true)` si el chofer acepta, o
/// `confirmed: false` si rechaza/descarta la oferta.
class OrderOfferDialog extends StackedView<OrderOfferDialogModel> {
  final DialogRequest request;
  final Function(DialogResponse) completer;

  const OrderOfferDialog({
    super.key,
    required this.request,
    required this.completer,
  });

  @override
  Widget builder(
    BuildContext context,
    OrderOfferDialogModel viewModel,
    Widget? child,
  ) {
    final data = (request.data is Map)
        ? Map<String, dynamic>.from(request.data as Map)
        : <String, dynamic>{};

    final items = (data['items'] is List) ? data['items'] as List : const [];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nuevo pedido',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            verticalSpaceSmall,
            Text(
              _formatTotal(data['totalAmount']),
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            verticalSpaceTiny,
            Text(
              _formatPaymentMethod(data['paymentMethod']),
              style: const TextStyle(fontSize: 14, color: kcMediumGrey),
            ),
            if (items.isNotEmpty) ...[
              verticalSpaceMedium,
              const Text(
                'Detalle',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              verticalSpaceTiny,
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${_formatItem(item)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
            verticalSpaceMedium,
            _buildCountdownBar(viewModel),
            verticalSpaceMedium,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      viewModel.stop();
                      completer(DialogResponse(confirmed: false));
                    },
                    child: const Text('Rechazar'),
                  ),
                ),
                horizontalSpaceSmall,
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kcPrimaryColor,
                    ),
                    onPressed: () {
                      viewModel.stop();
                      completer(DialogResponse(confirmed: true));
                    },
                    child: Text('Aceptar (${viewModel.remainingSeconds}s)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Barra + texto de la cuenta regresiva de la oferta. Cuando llega a 0 el
  /// modelo descarta la oferta solo (ver [OrderOfferDialogModel.start]).
  Widget _buildCountdownBar(OrderOfferDialogModel viewModel) {
    final remaining = viewModel.remainingSeconds;
    final fraction = (remaining / 30).clamp(0.0, 1.0);
    final color = remaining <= 10 ? Colors.red : kcPrimaryColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: kcVeryLightGrey,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        verticalSpaceTiny,
        Text(
          'La oferta vence en ${remaining}s',
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }

  String _formatTotal(dynamic totalAmount) {
    final value = (totalAmount is num) ? totalAmount.toDouble() : null;
    if (value == null) return 'Total no disponible';
    return _currencyFormat.format(value);
  }

  String _formatPaymentMethod(dynamic paymentMethod) {
    switch (paymentMethod?.toString()) {
      case 'cash':
        return 'Efectivo';
      case 'online':
        return 'Pago online';
      default:
        return paymentMethod?.toString() ?? 'Método de pago no informado';
    }
  }

  /// El shape exacto de cada item todavía no está 100% confirmado con el
  /// backend (ver TODO en HomeViewModel), así que se intenta leer las claves
  /// más probables y, si no calzan, se cae a mostrar el item crudo.
  String _formatItem(dynamic item) {
    if (item is! Map) return item.toString();
    final quantity = item['quantity'] ?? item['qty'];
    final name = item['name'] ??
        item['description'] ??
        item['cylinderType'] ??
        item['type'];
    if (name != null) {
      return quantity != null ? '${quantity}x $name' : '$name';
    }
    return item.toString();
  }

  @override
  OrderOfferDialogModel viewModelBuilder(BuildContext context) =>
      OrderOfferDialogModel();

  @override
  void onViewModelReady(OrderOfferDialogModel viewModel) {
    final data = (request.data is Map)
        ? Map<String, dynamic>.from(request.data as Map)
        : <String, dynamic>{};
    // Al vencer, se descarta la oferta como un rechazo (el backend ya la
    // re-ofreció a otro chofer). Mismo camino que tocar "Rechazar".
    viewModel.start(
      data['expiresAt'],
      () => completer(DialogResponse(confirmed: false)),
    );
    super.onViewModelReady(viewModel);
  }
}
