import 'package:dio/dio.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/driver_ops.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/ui/common/amount_input.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';
import 'package:splg_driver/ui/common/send_intent.dart';

/// Un gasto en edición: la categoría elegida y lo tipeado.
class ExpenseDraft {
  ExpenseDraft({this.categoryId, this.amount = '', this.description = ''});

  String? categoryId;
  String amount;
  String description;
}

/// Mi rendición del día (CU-232): lo esperado, el efectivo y los gastos que
/// declara el chofer y la presentación. Presentada, queda de sólo lectura.
class SettlementViewModel extends LoadViewModel {
  final _ops = locator<DriverOpsRepository>();

  Settlement? settlement;
  List<ExpenseCategory> categories = const [];

  String declaredCash = '';
  String notes = '';
  final List<ExpenseDraft> expenses = [];

  String? submitError;
  bool submitting = false;
  final _intent = SendIntent<void>();

  /// Con categorías de gasto se pueden declarar gastos; sin ellas, sólo el efectivo.
  bool get canDeclareExpenses => categories.isNotEmpty;

  bool get isEditable => settlement?.isOpen ?? false;

  @override
  Future<void> fetch() async {
    final s = await _ops.mySettlement();
    final cats =
        s.isOpen ? await _ops.expenseCategories() : const <ExpenseCategory>[];
    settlement = s;
    categories = cats;
  }

  void setDeclaredCash(String v) {
    declaredCash = v;
    _intent.reset();
    submitError = null;
    notifyListeners();
  }

  void setNotes(String v) {
    notes = v;
    _intent.reset();
  }

  void addExpense() {
    expenses.add(ExpenseDraft());
    _intent.reset();
    notifyListeners();
  }

  void removeExpense(ExpenseDraft e) {
    expenses.remove(e);
    _intent.reset();
    notifyListeners();
  }

  void updateExpense(ExpenseDraft e,
      {String? categoryId, String? amount, String? description}) {
    if (categoryId != null) e.categoryId = categoryId;
    if (amount != null) e.amount = amount;
    if (description != null) e.description = description;
    _intent.reset();
    submitError = null;
    notifyListeners();
  }

  num? get declaredValue => parseAmount(declaredCash);

  num? _expenseValue(ExpenseDraft e) => parseAmount(e.amount);

  int get _expensesCents =>
      expenses.fold<int>(0, (a, e) => a + toCents(_expenseValue(e) ?? 0));

  /// Diferencia que va a ver el administrador: declarado + gastos − esperado.
  num? get previewDifference {
    final d = declaredValue;
    final s = settlement;
    if (d == null || s == null) return null;
    return (toCents(d) + _expensesCents - toCents(s.expectedCash)) / 100;
  }

  /// Por qué no se puede presentar todavía, o null si está lista.
  String? get blocker {
    final d = declaredValue;
    if (d == null) {
      return 'Ingresá el efectivo que entregás, con coma para los centavos (0 si no cobraste).';
    }
    if (d < 0) return 'El efectivo no puede ser negativo.';
    for (final e in expenses) {
      final a = _expenseValue(e);
      if (e.categoryId == null) return 'Elegí la categoría de cada gasto.';
      if (a == null || a <= 0) {
        return 'El importe de cada gasto tiene que ser mayor que cero.';
      }
    }
    return null;
  }

  bool get canSubmit => isEditable && !submitting && blocker == null;

  Future<void> submit() async {
    final s = settlement;
    if (s == null || !canSubmit) return;
    submitError = null;
    submitting = true;
    notifyListeners();
    try {
      settlement = await _ops.submitSettlement(
        s.id,
        declaredCash: declaredValue!,
        expenses: [
          for (final e in expenses)
            ExpenseInput(
              categoryId: e.categoryId!,
              amount: _expenseValue(e)!,
              description: e.description,
            ),
        ],
        notes: notes,
        idempotencyKey: _intent.key,
      );
      _intent.reset();
    } catch (e) {
      submitError = actionErrorText(e);
      if (!keepIdempotencyKey(e)) _intent.reset();
      // Un 409 dice que el estado cambió (p. ej. ya estaba presentada): se
      // relee para mostrar el real.
      if (e is DioException && e.response?.statusCode == 409) {
        try {
          await fetch();
        } catch (_) {}
      }
    }
    submitting = false;
    notifyListeners();
  }
}
