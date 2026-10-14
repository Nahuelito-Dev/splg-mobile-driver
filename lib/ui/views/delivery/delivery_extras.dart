import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/ui/common/ui_helpers.dart';

import 'delivery_viewmodel.dart';

/// Tipos de incidencia que puede reportar el chofer. El primer valor de cada
/// tupla es el string exacto del enum `IncidentType` del backend.
const List<(String, String, IconData)> kIncidentTypes = [
  ('damaged', 'Garrafa dañada', SplgIcons.error),
  ('out_of_stock', 'Sin stock para entregar', SplgIcons.remove),
  ('no_show', 'El cliente no estaba', SplgIcons.userMinus),
  ('other', 'Otro problema', SplgIcons.more),
];

/// Hoja para reportar una incidencia: elegir tipo + describir, y enviar a
/// `POST /incidents` vía [DeliveryViewModel.reportIncident].
class IncidentSheet extends StatefulWidget {
  const IncidentSheet({required this.orderId, required this.viewModel});

  final String orderId;
  final DeliveryViewModel viewModel;

  @override
  State<IncidentSheet> createState() => IncidentSheetState();
}

class IncidentSheetState extends State<IncidentSheet> {
  String _type = kIncidentTypes.first.$1;
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
                children: kIncidentTypes
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

/// Tarjeta para cargar en el camión los envases físicos (por serial) que salen
/// para este pedido. Cada serial ingresado se agrega como chip; al despachar,
/// hace `POST /cylinders/assign` (filled→dispatched). Al confirmarse la entrega,
/// el backend los avanza solo a "con el cliente". Es opcional: distribuidoras
/// que no llevan control por serial simplemente no lo usan.
class CylinderAssignCard extends StatefulWidget {
  const CylinderAssignCard({required this.viewModel});

  final DeliveryViewModel viewModel;

  @override
  State<CylinderAssignCard> createState() => CylinderAssignCardState();
}

class CylinderAssignCardState extends State<CylinderAssignCard> {
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
              Icon(SplgIcons.flame,
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
                icon: const Icon(SplgIcons.plus),
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
