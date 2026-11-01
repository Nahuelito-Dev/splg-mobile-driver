import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/ui/widgets/labeled_field.dart';
import 'package:splg_driver/ui/widgets/load_scaffold.dart';
import 'settlement_viewmodel.dart';

/// "Mi rendición": lo esperado del día y la declaración del efectivo y los
/// gastos.
class SettlementView extends StackedView<SettlementViewModel> {
  const SettlementView({super.key});

  @override
  SettlementViewModel viewModelBuilder(BuildContext context) =>
      SettlementViewModel();

  @override
  void onViewModelReady(SettlementViewModel viewModel) => viewModel.load();

  @override
  Widget builder(
      BuildContext context, SettlementViewModel model, Widget? child) {
    final type = SplgType.of(context);
    return LoadScaffold(
      title: 'Mi rendición',
      centerTitle: false,
      model: model,
      builder: (context) {
        final s = model.settlement!;
        return RefreshIndicator(
          onRefresh: model.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: [
              SplgSoftCard(
                label: 'Efectivo esperado',
                amount: formatMoney(model.expectedCash ?? s.expectedCash),
                amountKey: const Key('settlement-expected'),
                caption: 'Rendición ${s.number} del ${s.businessDate} · '
                    '${s.status.label}',
              ),
              const SizedBox(height: 10),
              SplgButton(
                key: const Key('settlement-pdf'),
                title: 'Rendición (PDF)',
                style: SplgButtonStyle.outlined,
                loading: model.downloadingPdf,
                onPressed: model.canDownloadPdf ? model.downloadPdf : null,
              ),
              if (model.pdfError != null) ActionError(model.pdfError!),
              const SizedBox(height: 14),
              InfoRow('Pedidos en efectivo', '${s.orders.length}'),
              for (final o in s.orders) _EntregaRow(o),
              if (s.collections.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Cobros de cuenta corriente', style: type.subtitle),
                for (final c in s.collections)
                  InfoRow(c.businessName, formatMoney(c.amount)),
              ],
              const Divider(height: 28),
              if (s.isOpen) ..._form(context, model) else ..._result(s),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _result(Settlement s) => [
        InfoRow('Efectivo entregado',
            s.declaredCash == null ? '-' : formatMoney(s.declaredCash!)),
        InfoRow('Gastos', formatMoney(s.driverExpenses)),
        for (final e in s.expenses)
          InfoRow('  ${e.categoryName}', formatMoney(e.amount)),
        if (s.difference != null)
          InfoRow(
            s.difference! < 0
                ? 'Faltante'
                : (s.difference! > 0 ? 'Sobrante' : 'Diferencia'),
            formatMoney(s.difference!.abs()),
            strong: true,
          ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) => Text(
            s.status == SettlementStatus.approved
                ? 'La rendición está aprobada.'
                : 'Presentada: la revisa el administrador.',
            key: const Key('settlement-state'),
            style: SplgType.of(context).caption,
          ),
        ),
      ];

  List<Widget> _form(BuildContext context, SettlementViewModel model) {
    final type = SplgType.of(context);
    final diff = model.previewDifference;
    return [
      LabeledField(
        key: const Key('settlement-cash'),
        label: 'Efectivo que entregás',
        hint: '0',
        initial: model.declaredCash,
        number: true,
        enabled: !model.submitting,
        onChanged: model.setDeclaredCash,
      ),
      if (model.canDeclareExpenses) ...[
        Text('Gastos pagados con la cobranza', style: type.subtitle),
        const SizedBox(height: 8),
        for (final e in model.expenses)
          _ExpenseCard(key: ObjectKey(e), model: model, draft: e),
        SplgButton(
          key: const Key('settlement-add-expense'),
          title: 'Agregar gasto',
          style: SplgButtonStyle.outlined,
          onPressed: model.submitting ? null : model.addExpense,
        ),
        const SizedBox(height: 14),
      ],
      LabeledField(
        label: 'Notas (opcional)',
        initial: model.notes,
        maxLength: 500,
        lines: 3,
        enabled: !model.submitting,
        onChanged: model.setNotes,
      ),
      if (model.previewHint != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(model.previewHint!,
              key: const Key('settlement-preview-hint'), style: type.caption),
        ),
      if (diff != null)
        InfoRow(
          diff < 0
              ? 'Te faltarían'
              : (diff > 0 ? 'Te sobrarían' : 'Cierra justo'),
          diff == 0 ? '' : formatMoney(diff.abs()),
        ),
      const SizedBox(height: 10),
      if (model.submitError != null) ActionError(model.submitError!),
      if (model.blocker != null && model.declaredCash.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(model.blocker!, style: type.caption),
        ),
      SplgButton(
        key: const Key('settlement-submit'),
        title: 'Presentar rendición',
        loading: model.submitting,
        onPressed: model.canSubmit ? model.submit : null,
      ),
    ];
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({super.key, required this.model, required this.draft});

  final SettlementViewModel model;
  final ExpenseDraft draft;

  @override
  Widget build(BuildContext context) {
    final brasa = context.brasa;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: brasa.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            key: const Key('expense-category'),
            initialValue: draft.categoryId,
            decoration: SplgTextField.decoration(context),
            hint: const Text('Categoría'),
            items: [
              for (final c in model.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => model.updateExpense(draft, categoryId: v),
          ),
          const SizedBox(height: 10),
          LabeledField(
            label: 'Importe',
            initial: draft.amount,
            number: true,
            onChanged: (v) => model.updateExpense(draft, amount: v),
          ),
          LabeledField(
            label: 'Detalle (opcional)',
            initial: draft.description,
            maxLength: 255,
            onChanged: (v) => model.updateExpense(draft, description: v),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => model.removeExpense(draft),
              child: const Text('Quitar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una entrega de la rendición: el cliente y el monto, y debajo la dirección y
/// la hora para reconocerla.
class _EntregaRow extends StatelessWidget {
  const _EntregaRow(this.order);

  final SettlementOrder order;

  static String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final detalle = [
      if (order.deliveryAddress != null) order.deliveryAddress!,
      if (order.deliveredAt != null) formatDateTime(order.deliveredAt!),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(order.customerName ?? 'Pedido ${_short(order.orderId)}',
            formatMoney(order.amountToCollect)),
        if (detalle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(detalle, style: type.caption),
          ),
      ],
    );
  }
}
