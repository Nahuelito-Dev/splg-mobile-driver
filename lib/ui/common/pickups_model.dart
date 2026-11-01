import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/cylinder_pickup.dart';
import 'package:splg_driver/services/recovery_repository.dart';

/// Los retiros de envases de un pedido (CU-108, M5): lo que el cliente aceptó
/// devolver en esta entrega. Lo comparten la pantalla del viaje y la del pedido
/// completado (el back deja confirmar hasta 24 h después de la entrega).
///
/// Con el módulo apagado (o sin retiros en el pedido) [pickups] queda vacío y no
/// se muestra nada; un fallo al leer no se muestra: no es parte del viaje.
class PickupsModel extends ChangeNotifier {
  PickupsModel({required this.orderId, RecoveryRepository? repo})
      : _repoOverride = repo;

  final String orderId;
  final RecoveryRepository? _repoOverride;
  RecoveryRepository get _repo =>
      _repoOverride ?? locator<RecoveryRepository>();

  List<CylinderPickup> _pickups = const [];
  List<CylinderPickup> get pickups => _pickups;

  /// `noticeId` del retiro con una respuesta en vuelo.
  String? _busyId;
  bool isBusy(String noticeId) => _busyId == noticeId;
  bool get hasBusy => _busyId != null;

  /// Texto del último fallo al responder (el back lo rechazó o no hubo red).
  String? error;
  bool _disposed = false;

  /// Retiros ya confirmados en esta pantalla (se muestran como hechos).
  final Set<String> _done = {};
  bool isDone(String noticeId) => _done.contains(noticeId);

  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);

  /// Relee `GET …/driver/pickups` y se queda con los de este pedido. Con
  /// [every] sólo lo hace si pasó ese tiempo desde la última lectura.
  Future<void> load({Duration every = Duration.zero}) async {
    final now = DateTime.now();
    if (now.difference(_lastLoad) < every) return;
    _lastLoad = now;
    try {
      final all = await _repo.pickups();
      if (_disposed) return;
      _pickups = [
        for (final p in all)
          if (p.orderId == orderId) p,
        ..._pickups.where((p) => _done.contains(p.noticeId)),
      ];
      // Sin duplicar los ya hechos que el back todavía lista.
      final seen = <String>{};
      _pickups = [
        for (final p in _pickups)
          if (seen.add(p.noticeId)) p,
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('No se pudieron leer los retiros del pedido $orderId: $e');
    }
  }

  /// «Retiré el envase»: `POST …/confirm`.
  Future<bool> confirm(CylinderPickup p) => _answer(p, () async {
        await _repo.confirm(p.noticeId);
        _done.add(p.noticeId);
      });

  /// «No pude retirarlo»: `POST …/not-collected {reason}`. El motivo es
  /// obligatorio (1 a 500 caracteres).
  Future<bool> notCollected(CylinderPickup p, String reason) {
    final text = reason.trim();
    if (text.isEmpty) {
      error = 'Contanos por qué no pudiste retirarlo.';
      notifyListeners();
      return Future.value(false);
    }
    if (text.length > 500) {
      error = 'El motivo puede tener hasta 500 caracteres.';
      notifyListeners();
      return Future.value(false);
    }
    return _answer(p, () async {
      await _repo.notCollected(p.noticeId, reason: text);
      _pickups = [
        for (final x in _pickups)
          if (x.noticeId != p.noticeId) x,
      ];
    });
  }

  Future<bool> _answer(CylinderPickup p, Future<void> Function() call) async {
    if (_busyId != null) return false;
    _busyId = p.noticeId;
    error = null;
    notifyListeners();
    var ok = false;
    try {
      await call();
      ok = true;
    } catch (e) {
      debugPrint('Error respondiendo el retiro ${p.noticeId}: $e');
      error = _errorText(e);
    }
    _busyId = null;
    if (!_disposed) notifyListeners();
    return ok;
  }

  /// El 403 del back es el plazo de 24 h vencido (o el pedido cancelado): su
  /// texto explica más que el genérico de «sin permiso».
  static String _errorText(Object e) {
    if (e is DioException && e.response?.statusCode == 403) {
      final data = e.response?.data;
      final m = data is Map ? data['message'] : null;
      final text = m is List ? m.join(' ') : m?.toString();
      if (text != null && text.isNotEmpty) return text;
    }
    return actionErrorText(e,
        fallback: 'No pudimos registrar el retiro. Probá de nuevo.');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
