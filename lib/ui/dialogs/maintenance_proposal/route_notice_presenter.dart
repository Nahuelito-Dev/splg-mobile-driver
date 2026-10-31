import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/models/maintenance.dart';
import 'package:splg_driver/services/maintenance_notifier.dart';
import 'maintenance_proposal_dialog.dart';

/// Muestra el aviso como una ruta propia del navegador raíz y lo cierra por la
/// identidad de esa ruta ([NavigatorState.removeRoute]): no importa qué otra
/// pantalla o diálogo haya quedado encima, nunca se cierra otro por error.
class RouteNoticePresenter implements NoticePresenter {
  @override
  NoticeHandle show(MaintenanceProposal proposal) {
    final navigator = StackedService.navigatorKey?.currentState;
    final completer = Completer<NoticeAction?>();
    if (navigator == null) {
      completer.complete(null);
      return _RouteHandle(completer, null, null);
    }
    late final DialogRoute<void> route;
    void finish(NoticeAction? action) {
      if (!completer.isCompleted) completer.complete(action);
      if (route.isActive) navigator.removeRoute(route);
    }

    route = DialogRoute<void>(
      context: navigator.context,
      barrierDismissible: true,
      builder: (_) => MaintenanceProposalDialog(
        proposal: proposal,
        onAction: finish,
      ),
    );
    // Tocar afuera (o "atrás") equivale a "Después".
    route.popped.then((_) => finish(NoticeAction.later));
    navigator.push(route);
    return _RouteHandle(completer, navigator, route);
  }
}

class _RouteHandle implements NoticeHandle {
  _RouteHandle(this._completer, this._navigator, this._route);

  final Completer<NoticeAction?> _completer;
  final NavigatorState? _navigator;
  final Route<void>? _route;

  @override
  Future<NoticeAction?> get result => _completer.future;

  @override
  void dismiss() {
    if (!_completer.isCompleted) _completer.complete(null);
    final r = _route;
    if (r != null && r.isActive) _navigator?.removeRoute(r);
  }
}
