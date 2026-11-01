import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/route_batch.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_socket_service.dart';
import 'package:splg_driver/services/route_batch_repository.dart';

/// Cómo terminó la oferta del recorrido en pantalla.
enum BatchOutcome {
  /// El back asignó los pedidos.
  accepted,

  /// El back contestó que no (409 vencida o ya no es suya, 400…): no se insiste.
  refused,

  /// «Rechazar»: la respuesta al back la manda quien abrió la pantalla.
  rejected,

  /// Venció la cuenta regresiva: el back ya cerró la oferta.
  expired,

  /// El despacho retiró la oferta (`route-batch:offer-closed`).
  closed,
}

/// Datos de la oferta de un recorrido: cuenta regresiva hasta `offer.expiresAt`
/// (del servidor) y la respuesta del chofer.
///
/// Igual que la oferta suelta: **la cuenta se detiene al tocar «Aceptar» y el
/// POST va antes de cualquier otra cosa.** Si no hay respuesta del back (red)
/// la cuenta sigue y se puede reintentar con la misma clave de idempotencia.
class RouteBatchOfferDialogModel extends BaseViewModel {
  RouteBatchOfferDialogModel({
    required this.batch,
    RouteBatchRepository? repo,
    Stream<RouteBatchEvent>? events,
    DateTime Function()? now,
  })  : _repoOverride = repo,
        _eventsOverride = events,
        _now = now ?? DateTime.now;

  final RouteBatch batch;
  final RouteBatchRepository? _repoOverride;
  final Stream<RouteBatchEvent>? _eventsOverride;
  final DateTime Function() _now;

  RouteBatchRepository get _repo =>
      _repoOverride ?? locator<RouteBatchRepository>();
  Stream<RouteBatchEvent> get _events =>
      _eventsOverride ?? locator<DriverSocketService>().routeBatchEvents;

  Timer? _timer;
  StreamSubscription<RouteBatchEvent>? _eventsSub;
  void Function(BatchOutcome)? _onDone;
  bool _done = false;

  int _remainingSeconds = 0;
  int get remainingSeconds => _remainingSeconds;
  int _totalSeconds = 60;

  /// Segundos con los que arrancó la cuenta (el 100 % de la barra).
  int get totalSeconds => _totalSeconds;

  bool _accepting = false;
  bool get isAccepting => _accepting;

  /// La oferta ya se resolvió (aceptó, rechazó, venció o se cerró).
  bool get isFinished => _done;

  /// Texto del último fallo al aceptar.
  String? acceptError;

  List<RouteBatchStop> get stops => batch.stops;

  /// Arranca la cuenta y escucha los cierres. [onDone] se llama una sola vez.
  void start(void Function(BatchOutcome) onDone) {
    _onDone = onDone;
    final left = batch.offer?.remaining(_now()).inSeconds ?? 0;
    _remainingSeconds = left;
    _totalSeconds = left < 1 ? 1 : left;
    _eventsSub = _events.listen((e) {
      // Con el POST en vuelo manda su respuesta, no el aviso.
      if (e is RouteBatchClosed && e.batchId == batch.batchId && !_accepting) {
        _finish(BatchOutcome.closed);
      }
    });
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final expires = batch.offer?.expiresAt;
      _remainingSeconds = expires == null
          ? _remainingSeconds - 1
          : expires.difference(_now().toUtc()).inSeconds;
      if (_remainingSeconds <= 0) {
        _remainingSeconds = 0;
        _finish(BatchOutcome.expired);
        return;
      }
      notifyListeners();
    });
  }

  void _finish(BatchOutcome outcome) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    notifyListeners();
    _onDone?.call(outcome);
  }

  /// «Rechazar» (o volver): frena la cuenta y cierra.
  void reject() {
    if (_accepting) return;
    _finish(BatchOutcome.rejected);
  }

  /// «Aceptar recorrido»: frena la cuenta y acepta en el back ANTES de
  /// cualquier otra cosa. Sin respuesta (red) la cuenta sigue y se puede
  /// reintentar.
  Future<void> accept() async {
    if (_accepting || _done) return;
    _accepting = true;
    acceptError = null;
    _timer?.cancel();
    notifyListeners();
    try {
      await _repo.accept(batch.batchId);
      _accepting = false;
      _finish(BatchOutcome.accepted);
    } catch (e) {
      debugPrint('No se pudo aceptar el recorrido ${batch.batchId}: $e');
      _accepting = false;
      if (e is DioException && e.response != null) {
        acceptError = DriverApiService.errorMessage(e);
        _finish(BatchOutcome.refused);
      } else {
        acceptError = actionErrorText(e,
            fallback: 'Sin conexión. Probá de nuevo antes de que venza.');
        _startTimer();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
