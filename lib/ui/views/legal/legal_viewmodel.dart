import 'package:flutter/services.dart' show rootBundle;
import 'package:stacked/stacked.dart';

import 'legal_view.dart' show LegalDocument;

/// Carga el contenido markdown de un documento legal (Términos y
/// Condiciones o Política de Privacidad) desde los assets de la app.
class LegalViewModel extends BaseViewModel {
  LegalViewModel({required this.document});

  final LegalDocument document;

  String? _content;
  String? get content => _content;

  bool _hasError = false;
  @override
  bool get hasError => _hasError;

  String get title => document.title;

  Future<void> initialize() async {
    setBusy(true);
    try {
      _content = await rootBundle.loadString(document.assetPath);
      _hasError = false;
    } catch (_) {
      _hasError = true;
    }
    setBusy(false);
  }
}
