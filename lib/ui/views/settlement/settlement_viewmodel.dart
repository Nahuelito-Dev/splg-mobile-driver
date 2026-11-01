import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  SettlementViewModel({
    Future<bool> Function(Uint8List bytes, String filename)? sharePdf,
    this.previewDebounce = const Duration(milliseconds: 400),
  }) : _sharePdf = sharePdf ?? _nativeShare;

  /// Espera sin teclear antes de pedirle al back la diferencia.
  final Duration previewDebounce;

  /// Hoja nativa para ver, guardar o compartir el PDF (iOS y Android).
  static Future<bool> _nativeShare(Uint8List bytes, String filename) async {
    // Se escribe a un archivo con su nombre: con datos en memoria iOS muestra
    // la hoja sin nombre ni vista previa.
    final dir = await getTemporaryDirectory();
    final archivo = File('${dir.path}/$filename');
    await archivo.writeAsBytes(bytes, flush: true);
    final resultado = await SharePlus.instance.share(ShareParams(
      files: [XFile(archivo.path, mimeType: 'application/pdf')],
      // En iOS el encabezado de la hoja muestra el título, no el nombre del archivo.
      title: filename,
    ));
    return resultado.status != ShareResultStatus.unavailable;
  }

  final Future<bool> Function(Uint8List bytes, String filename) _sharePdf;
  final _ops = locator<DriverOpsRepository>();

  Settlement? settlement;
  List<ExpenseCategory> categories = const [];

  String declaredCash = '';
  String notes = '';
  final List<ExpenseDraft> expenses = [];

  /// Lo que calculó el back para lo que hay escrito (esperado en vivo y
  /// diferencia); null mientras no lo tenga o si la consulta falló: la app no
  /// lo inventa.
  SettlementPreview? preview;
  num? get previewDifference => preview?.difference;

  num? _freshExpected;

  /// El efectivo esperado que se muestra: el de la última vista previa que
  /// contestó el back (el más fresco), y si todavía no hubo, el de la lectura
  /// de la rendición.
  num? get expectedCash => _freshExpected ?? settlement?.expectedCash;

  /// Aviso cuando un gasto tiene un importe que no se puede leer: sin ese
  /// importe el back no puede calcular la diferencia.
  String? get previewHint => expenses.any(_expenseUnreadable)
      ? 'Revisá el importe del gasto: no se puede calcular la diferencia.'
      : null;

  bool _expenseUnreadable(ExpenseDraft e) =>
      e.amount.trim().isNotEmpty && _expenseValue(e) == null;
  Timer? _previewTimer;
  int _previewRun = 0;

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
    _freshExpected = null;
    // La lectura trae un esperado nuevo: se vuelve a pedir la diferencia.
    _schedulePreview();
  }

  void setDeclaredCash(String v) {
    declaredCash = v;
    _intent.reset();
    submitError = null;
    _schedulePreview();
    notifyListeners();
  }

  void setNotes(String v) {
    notes = v;
    _intent.reset();
  }

  void addExpense() {
    expenses.add(ExpenseDraft());
    _intent.reset();
    _schedulePreview();
    notifyListeners();
  }

  void removeExpense(ExpenseDraft e) {
    expenses.remove(e);
    _intent.reset();
    _schedulePreview();
    notifyListeners();
  }

  void updateExpense(ExpenseDraft e,
      {String? categoryId, String? amount, String? description}) {
    if (categoryId != null) e.categoryId = categoryId;
    if (amount != null) e.amount = amount;
    if (description != null) e.description = description;
    _intent.reset();
    submitError = null;
    _schedulePreview();
    notifyListeners();
  }

  bool downloadingPdf = false;
  String? pdfError;

  /// Se puede bajar el PDF de la rendición en cualquier estado.
  bool get canDownloadPdf => settlement != null && !downloadingPdf;

  Future<void> downloadPdf() async {
    final s = settlement;
    if (s == null || downloadingPdf) return;
    pdfError = null;
    downloadingPdf = true;
    notifyListeners();
    try {
      final bytes = await _ops.settlementPdf(s.id);
      await _sharePdf(bytes, 'rendicion-${s.number}.pdf');
    } catch (e) {
      pdfError = actionErrorText(e);
    }
    downloadingPdf = false;
    notifyListeners();
  }

  num? get declaredValue => parseAmount(declaredCash);

  num? _expenseValue(ExpenseDraft e) => parseAmount(e.amount);

  /// Los importes de los gastos que ya se pueden leer: lo que está a medio
  /// tipear (vacío, 0) no entra en la consulta.
  List<num> get _expenseAmounts => [
        for (final e in expenses)
          if ((_expenseValue(e) ?? 0) > 0) _expenseValue(e)!,
      ];

  /// Pide la diferencia al back cuando el chofer deja de teclear. Sin efectivo
  /// legible o sin red no hay diferencia: se oculta, no se calcula acá.
  void _schedulePreview() {
    _previewTimer?.cancel();
    final run = ++_previewRun;
    preview = null;
    final s = settlement;
    final declared = declaredValue;
    if (s == null || !isEditable || declared == null) return;
    if (expenses.any(_expenseUnreadable)) return;
    final amounts = _expenseAmounts;
    _previewTimer = Timer(previewDebounce, () async {
      SettlementPreview? result;
      try {
        result = await _ops.previewSettlement(s.id,
            declaredCash: declared, expenseAmounts: amounts);
      } catch (_) {
        result = null;
      }
      // Una respuesta lenta de un valor viejo no pisa a la del valor actual.
      if (run != _previewRun) return;
      preview = result;
      if (result != null) _freshExpected = result.expectedCash;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
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
    _previewTimer?.cancel();
    _previewRun++;
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
