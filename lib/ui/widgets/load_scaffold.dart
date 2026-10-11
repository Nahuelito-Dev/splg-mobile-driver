import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/ui/common/load_view_model.dart';
import 'package:splg_driver/ui/widgets/driver_header.dart';

/// Pantalla interna con encabezado y los tres estados de una lectura:
/// cargando, error con "Reintentar" y contenido.
class LoadScaffold extends StatelessWidget {
  const LoadScaffold({
    super.key,
    required this.title,
    required this.model,
    required this.builder,
    this.centerTitle = true,
    this.bell = true,
  });

  final String title;
  final LoadViewModel model;
  final WidgetBuilder builder;
  final bool centerTitle;
  final bool bell;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (model.isBusy) {
      body = const Center(child: CircularProgressIndicator());
    } else if (model.loadError != null) {
      body = SplgEmptyState(
        illustration: SplgIllustration.error,
        title: 'No pudimos cargar',
        message: model.loadError!,
        action: SplgButton(
          title: 'Reintentar',
          style: SplgButtonStyle.outlined,
          expand: false,
          onPressed: model.load,
        ),
      );
    } else {
      body = builder(context);
    }
    return Scaffold(
      appBar: DriverHeader(title: title, centerTitle: centerTitle, bell: bell),
      body: SafeArea(child: body),
    );
  }
}
