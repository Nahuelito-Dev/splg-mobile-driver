import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/ui/widgets/driver_header.dart';
import 'legal_viewmodel.dart';

/// Documento legal que puede mostrar [LegalView].
enum LegalDocument {
  terms,
  privacy;

  String get title => switch (this) {
        LegalDocument.terms => 'Términos y Condiciones',
        LegalDocument.privacy => 'Política de Privacidad',
      };

  /// Ruta del asset markdown (declarado en pubspec.yaml bajo `legal/`).
  String get assetPath => switch (this) {
        LegalDocument.terms => 'legal/terminos-y-condiciones.md',
        LegalDocument.privacy => 'legal/politica-de-privacidad.md',
      };
}

/// Pantalla reutilizable para mostrar Términos y Condiciones o la Política
/// de Privacidad, renderizando el markdown provisto en `legal/`. Son los
/// mismos documentos legales de la plataforma que usa la app cliente.
class LegalView extends StackedView<LegalViewModel> {
  const LegalView({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget builder(
    BuildContext context,
    LegalViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      appBar: DriverHeader(title: viewModel.title, bell: false),
      body: SafeArea(child: _buildBody(context, viewModel)),
    );
  }

  Widget _buildBody(BuildContext context, LegalViewModel viewModel) {
    final theme = Theme.of(context);
    final type = SplgType.of(context);

    if (viewModel.isBusy) {
      return const Center(child: CircularProgressIndicator());
    }

    if (viewModel.hasError || viewModel.content == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No pudimos cargar este documento. Intentá nuevamente más tarde.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Markdown(
      data: viewModel.content!,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        h1: type.title.copyWith(fontSize: context.sp(14)),
        h2: type.heading.copyWith(fontSize: context.sp(13)),
        h3: type.subtitle,
        p: type.body.copyWith(height: 1.4),
      ),
    );
  }

  @override
  void onViewModelReady(LegalViewModel viewModel) {
    viewModel.initialize();
    super.onViewModelReady(viewModel);
  }

  @override
  LegalViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      LegalViewModel(document: document);
}
