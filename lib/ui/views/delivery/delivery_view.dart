import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/ui/common/ui_helpers.dart';

import 'delivery_viewmodel.dart';
import 'package:splg_lib/theme/app_colors.dart';
import 'package:splg_lib/theme/brasa_palette.dart';

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
            _buildErrorBanner(context, viewModel.errorMessage!),
            verticalSpaceMedium,
          ],
          _buildStatusChip(context, viewModel),
          verticalSpaceMedium,
          _buildOrderCard(context, viewModel),
          verticalSpaceLarge,
          if (viewModel.isAccepted || viewModel.isOnTheWay) ...[
            _CylinderAssignCard(viewModel: viewModel),
            verticalSpaceMedium,
          ],
          if (viewModel.isAccepted) ...[
            _buildOnTheWayButton(context, viewModel),
            verticalSpaceMedium,
          ],
          _buildNavigateButton(context, viewModel),
          verticalSpaceMedium,
          if (viewModel.isOnTheWay && !viewModel.arrivedNotified) ...[
            _buildArrivedButton(context, viewModel),
            verticalSpaceMedium,
          ],
          _buildQrSection(context, viewModel),
          verticalSpaceMedium,
          _buildIncidentButton(context, viewModel),
        ],
      ),
    );
  }

  /// Botón discreto para reportar un problema con la entrega (garrafa dañada,
  /// sin stock, cliente ausente, otro). Abre una hoja para elegir el tipo y
  /// describirlo, y hace `POST /incidents`.
  Widget _buildIncidentButton(
    BuildContext context,
    DeliveryViewModel viewModel,
  ) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: viewModel.isReportingIncident
            ? null
            : () => _showIncidentSheet(context, viewModel),
        icon: Icon(Icons.report_problem_outlined,
            size: 20, color: context.brasa.danger),
        label: Text(
          'Reportar un problema',
          style: TextStyle(color: context.brasa.danger),
        ),
      ),
    );
  }

  Future<void> _showIncidentSheet(
    BuildContext context,
    DeliveryViewModel viewModel,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) =>
          _IncidentSheet(orderId: orderId, viewModel: viewModel),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.brasa.dangerSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brasa.danger),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: context.brasa.danger, size: 20),
          horizontalSpaceSmall,
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.brasa.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, DeliveryViewModel viewModel) {
    final String label;
    final Color color;
    if (viewModel.isOnTheWay) {
      label = 'En camino';
      color = Theme.of(context).colorScheme.primary;
    } else if (viewModel.isAccepted) {
      label = 'Aceptado, falta salir';
      color = context.brasa.warn;
    } else {
      label = viewModel.status ?? 'Sin estado';
      color = context.brasa.muted;
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
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, DeliveryViewModel viewModel) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.brasa.outline.withAlpha(120),
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
            style: TextStyle(fontSize: 13, color: context.brasa.muted),
          ),
          if (viewModel.items.isNotEmpty) ...[
            verticalSpaceMedium,
            const Text('Detalle',
                style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildOnTheWayButton(
      BuildContext context, DeliveryViewModel viewModel) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: viewModel.isUpdatingStatus ? null : viewModel.markOnTheWay,
        icon: viewModel.isUpdatingStatus
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.play_arrow),
        label: const Text('En camino'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildArrivedButton(
      BuildContext context, DeliveryViewModel viewModel) {
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

  Widget _buildNavigateButton(
      BuildContext context, DeliveryViewModel viewModel) {
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

  Widget _buildQrSection(BuildContext context, DeliveryViewModel viewModel) {
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
                style: TextStyle(color: context.brasa.danger, fontSize: 13),
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brasa.outline),
      ),
      child: Column(
        children: [
          QrImageView(
            data: viewModel.deliveryCode!,
            size: 220,
            backgroundColor: Theme.of(context).colorScheme.surface,
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
          Text(
            'Mostrale este QR al cliente para confirmar la entrega',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.brasa.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveredBody(
      BuildContext context, DeliveryViewModel viewModel) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          verticalSpaceLarge,
          Icon(Icons.check_circle, color: context.brasa.success, size: 96),
          verticalSpaceLarge,
          const Text(
            '¡Entrega confirmada!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          verticalSpaceSmall,
          Text(
            'El cliente confirmó la entrega escaneando el QR.',
            style: TextStyle(fontSize: 14, color: context.brasa.muted),
            textAlign: TextAlign.center,
          ),
          verticalSpaceLarge,
          _CustomerRatingCard(viewModel: viewModel),
          verticalSpaceLarge,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: viewModel.goHome,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Volver al inicio'),
            ),
          ),
        ],
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

/// Tipos de incidencia que puede reportar el chofer. El primer valor de cada
/// tupla es el string exacto del enum `IncidentType` del backend.
const List<(String, String, IconData)> _incidentTypes = [
  ('damaged', 'Garrafa dañada', Icons.report_gmailerrorred_outlined),
  ('out_of_stock', 'Sin stock para entregar', Icons.inventory_2_outlined),
  ('no_show', 'El cliente no estaba', Icons.person_off_outlined),
  ('other', 'Otro problema', Icons.more_horiz),
];

/// Hoja para reportar una incidencia: elegir tipo + describir, y enviar a
/// `POST /incidents` vía [DeliveryViewModel.reportIncident].
class _IncidentSheet extends StatefulWidget {
  const _IncidentSheet({required this.orderId, required this.viewModel});

  final String orderId;
  final DeliveryViewModel viewModel;

  @override
  State<_IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<_IncidentSheet> {
  String _type = _incidentTypes.first.$1;
  final _descriptionController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contanos qué pasó antes de enviar.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final ok = await widget.viewModel.reportIncident(
      type: _type,
      description: description,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Incidencia reportada. La distribuidora fue notificada.'
            : (widget.viewModel.errorMessage ??
                'No se pudo reportar la incidencia.')),
        backgroundColor: ok ? context.brasa.success : context.brasa.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reportar un problema',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          verticalSpaceMedium,
          IgnorePointer(
            ignoring: _submitting,
            child: RadioGroup<String>(
              groupValue: _type,
              onChanged: (value) => setState(() => _type = value ?? _type),
              child: Column(
                children: _incidentTypes
                    .map(
                      (t) => RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: t.$1,
                        title: Row(
                          children: [
                            Icon(t.$3, size: 20, color: context.brasa.muted),
                            horizontalSpaceSmall,
                            Text(t.$2),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          verticalSpaceSmall,
          TextField(
            controller: _descriptionController,
            enabled: !_submitting,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Contá brevemente qué pasó',
              border: OutlineInputBorder(),
            ),
          ),
          verticalSpaceMedium,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.brasa.danger,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Enviar reporte'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta para calificar al cliente una vez confirmada la entrega
/// (`POST /ratings`). Guarda las estrellas + comentario opcional localmente y
/// delega el envío al [DeliveryViewModel]. Una vez enviada, muestra el
/// agradecimiento.
class _CustomerRatingCard extends StatefulWidget {
  const _CustomerRatingCard({required this.viewModel});

  final DeliveryViewModel viewModel;

  @override
  State<_CustomerRatingCard> createState() => _CustomerRatingCardState();
}

class _CustomerRatingCardState extends State<_CustomerRatingCard> {
  int _stars = 0;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await widget.viewModel.rateCustomer(
      stars: _stars,
      comment: _commentController.text,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Gracias por calificar!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;

    if (viewModel.ratingSubmitted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.brasa.outline.withAlpha(120),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star, color: AppColors.gas400),
            horizontalSpaceSmall,
            Text('¡Gracias por calificar al cliente!'),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.brasa.outline.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calificá al cliente',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          verticalSpaceSmall,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                iconSize: 36,
                onPressed: viewModel.isSubmittingRating
                    ? null
                    : () => setState(() => _stars = value),
                icon: Icon(
                  value <= _stars ? Icons.star : Icons.star_border,
                  color: AppColors.gas400,
                ),
              );
            }),
          ),
          TextField(
            controller: _commentController,
            enabled: !viewModel.isSubmittingRating,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Comentario (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (viewModel.ratingError != null) ...[
            verticalSpaceSmall,
            Text(
              viewModel.ratingError!,
              style: TextStyle(color: context.brasa.danger, fontSize: 13),
            ),
          ],
          verticalSpaceMedium,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_stars == 0 || viewModel.isSubmittingRating)
                  ? null
                  : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: viewModel.isSubmittingRating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Enviar calificación'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta para cargar en el camión los envases físicos (por serial) que salen
/// para este pedido. Cada serial ingresado se agrega como chip; al despachar,
/// hace `POST /cylinders/assign` (filled→dispatched). Al confirmarse la entrega,
/// el backend los avanza solo a "con el cliente". Es opcional: distribuidoras
/// que no llevan control por serial simplemente no lo usan.
class _CylinderAssignCard extends StatefulWidget {
  const _CylinderAssignCard({required this.viewModel});

  final DeliveryViewModel viewModel;

  @override
  State<_CylinderAssignCard> createState() => _CylinderAssignCardState();
}

class _CylinderAssignCardState extends State<_CylinderAssignCard> {
  final _serialController = TextEditingController();
  final List<String> _serials = [];

  @override
  void dispose() {
    _serialController.dispose();
    super.dispose();
  }

  void _addSerial() {
    final value = _serialController.text.trim();
    if (value.isEmpty) return;
    if (_serials.contains(value)) {
      _serialController.clear();
      return;
    }
    setState(() {
      _serials.add(value);
      _serialController.clear();
    });
  }

  Future<void> _dispatch() async {
    if (_serials.isEmpty) return;
    final ok = await widget.viewModel.assignCylinders(List.of(_serials));
    if (ok && mounted) {
      setState(() => _serials.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Envases despachados')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brasa.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.propane_tank_outlined,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              horizontalSpaceSmall,
              const Text(
                'Envases del pedido',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (viewModel.assignedCylinders > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.brasa.successSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${viewModel.assignedCylinders} despachado(s)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: context.brasa.success,
                    ),
                  ),
                ),
            ],
          ),
          verticalSpaceSmall,
          Text(
            'Cargá los seriales de las garrafas que salen para este pedido.',
            style: TextStyle(fontSize: 13, color: context.brasa.muted),
          ),
          verticalSpaceMedium,
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serialController,
                  enabled: !viewModel.isAssigningCylinders,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _addSerial(),
                  decoration: const InputDecoration(
                    labelText: 'Número de serie',
                    hintText: 'Ej: SN-000123',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              horizontalSpaceSmall,
              IconButton.filled(
                onPressed: viewModel.isAssigningCylinders ? null : _addSerial,
                style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (_serials.isNotEmpty) ...[
            verticalSpaceSmall,
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _serials
                  .map(
                    (s) => Chip(
                      label: Text(s),
                      onDeleted: viewModel.isAssigningCylinders
                          ? null
                          : () => setState(() => _serials.remove(s)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (viewModel.cylinderError != null) ...[
            verticalSpaceSmall,
            Text(
              viewModel.cylinderError!,
              style: TextStyle(fontSize: 12, color: context.brasa.danger),
            ),
          ],
          verticalSpaceMedium,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_serials.isEmpty || viewModel.isAssigningCylinders)
                  ? null
                  : _dispatch,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: viewModel.isAssigningCylinders
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Text(
                      _serials.isEmpty
                          ? 'Despachar envases'
                          : 'Despachar ${_serials.length} envase(s)',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
