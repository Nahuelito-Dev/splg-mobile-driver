import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:stacked/stacked.dart';

import 'package:driver_mobile/ui/common/app_colors.dart';
import 'package:driver_mobile/ui/common/ui_helpers.dart';

import 'delivery_viewmodel.dart';

final _currencyFormat =
    NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);

/// Pantalla de entrega en curso: desde que el chofer acepta el pedido hasta
/// que el cliente confirma la entrega escaneando el QR.
class DeliveryView extends StackedView<DeliveryViewModel> {
  final String orderId;

  const DeliveryView({super.key, required this.orderId});

  @override
  Widget builder(
    BuildContext context,
    DeliveryViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrega en curso'),
        automaticallyImplyLeading: !viewModel.isDelivered,
      ),
      body: SafeArea(
        child: viewModel.isBusy
            ? const Center(child: CircularProgressIndicator())
            : viewModel.isDelivered
                ? _buildDeliveredBody(context, viewModel)
                : _buildBody(context, viewModel),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DeliveryViewModel viewModel) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewModel.errorMessage != null) ...[
            _buildErrorBanner(viewModel.errorMessage!),
            verticalSpaceMedium,
          ],
          _buildStatusChip(viewModel),
          verticalSpaceMedium,
          _buildOrderCard(viewModel),
          verticalSpaceLarge,
          if (viewModel.isAccepted) ...[
            _buildOnTheWayButton(viewModel),
            verticalSpaceMedium,
          ],
          _buildNavigateButton(context, viewModel),
          verticalSpaceMedium,
          if (viewModel.isOnTheWay && !viewModel.arrivedNotified) ...[
            _buildArrivedButton(viewModel),
            verticalSpaceMedium,
          ],
          _buildQrSection(viewModel),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          horizontalSpaceSmall,
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(DeliveryViewModel viewModel) {
    final String label;
    final Color color;
    if (viewModel.isOnTheWay) {
      label = 'En camino';
      color = kcPrimaryColor;
    } else if (viewModel.isAccepted) {
      label = 'Aceptado, falta salir';
      color = Colors.orange;
    } else {
      label = viewModel.status ?? 'Sin estado';
      color = kcMediumGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_shipping, color: Colors.white, size: 16),
          horizontalSpaceTiny,
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(DeliveryViewModel viewModel) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kcVeryLightGrey.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 20),
              horizontalSpaceSmall,
              Expanded(
                child: Text(
                  viewModel.addressText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          verticalSpaceSmall,
          Text(
            _currencyFormat.format(viewModel.total),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          verticalSpaceTiny,
          Text(
            _formatPaymentMethod(viewModel.paymentMethod),
            style: const TextStyle(fontSize: 13, color: kcMediumGrey),
          ),
          if (viewModel.items.isNotEmpty) ...[
            verticalSpaceMedium,
            const Text('Detalle', style: TextStyle(fontWeight: FontWeight.bold)),
            verticalSpaceTiny,
            ...viewModel.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${_formatItem(item)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOnTheWayButton(DeliveryViewModel viewModel) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: viewModel.isUpdatingStatus ? null : viewModel.markOnTheWay,
        icon: viewModel.isUpdatingStatus
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.play_arrow),
        label: const Text('En camino'),
        style: ElevatedButton.styleFrom(
          backgroundColor: kcPrimaryColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildArrivedButton(DeliveryViewModel viewModel) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: viewModel.markArrived,
        icon: const Icon(Icons.location_on),
        label: const Text('Avisar que llegué'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildNavigateButton(BuildContext context, DeliveryViewModel viewModel) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: viewModel.hasCoordinates
            ? () => _showNavigateOptions(context, viewModel)
            : null,
        icon: const Icon(Icons.navigation_outlined),
        label: const Text('Navegar'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _showNavigateOptions(
    BuildContext context,
    DeliveryViewModel viewModel,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.navigation),
                title: const Text('Abrir en Waze'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  viewModel.openWaze();
                },
              ),
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Abrir en Google Maps'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  viewModel.openGoogleMaps();
                },
              ),
              verticalSpaceSmall,
            ],
          ),
        );
      },
    );
  }

  Widget _buildQrSection(DeliveryViewModel viewModel) {
    if (viewModel.deliveryCode == null) {
      return SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed:
                  viewModel.isLoadingQr ? null : viewModel.showDeliveryCode,
              icon: viewModel.isLoadingQr
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2),
              label: const Text('Mostrar QR de entrega'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
            if (viewModel.qrError != null) ...[
              verticalSpaceSmall,
              Text(
                viewModel.qrError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kcVeryLightGrey),
      ),
      child: Column(
        children: [
          QrImageView(
            data: viewModel.deliveryCode!,
            size: 220,
            backgroundColor: Colors.white,
          ),
          verticalSpaceMedium,
          Text(
            viewModel.deliveryCode!,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          verticalSpaceSmall,
          const Text(
            'Mostrale este QR al cliente para confirmar la entrega',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: kcMediumGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveredBody(BuildContext context, DeliveryViewModel viewModel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 96),
            verticalSpaceLarge,
            const Text(
              '¡Entrega confirmada!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            verticalSpaceSmall,
            Text(
              'El cliente confirmó la entrega escaneando el QR.',
              style: const TextStyle(fontSize: 14, color: kcMediumGrey),
              textAlign: TextAlign.center,
            ),
            verticalSpaceLarge,
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: viewModel.goHome,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kcPrimaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Volver al inicio'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPaymentMethod(String? paymentMethod) {
    switch (paymentMethod) {
      case 'cash':
        return 'Efectivo';
      case 'online':
        return 'Pago online';
      default:
        return paymentMethod ?? 'Método de pago no informado';
    }
  }

  /// Igual criterio que `OrderOfferDialog._formatItem`: el shape exacto de
  /// `gas_cylinder` puede variar, así que se intentan las claves más
  /// probables y se cae al item crudo si no calzan.
  String _formatItem(Map<String, dynamic> item) {
    final quantity = item['quantity'];
    final cylinder = item['gas_cylinder'];
    final name = (cylinder is Map)
        ? (cylinder['description'] ?? cylinder['type'])
        : null;
    if (name != null) {
      return quantity != null ? '${quantity}x $name' : '$name';
    }
    return item.toString();
  }

  @override
  DeliveryViewModel viewModelBuilder(BuildContext context) =>
      DeliveryViewModel(orderId: orderId);

  @override
  void onViewModelReady(DeliveryViewModel viewModel) {
    viewModel.initialize();
    super.onViewModelReady(viewModel);
  }
}
