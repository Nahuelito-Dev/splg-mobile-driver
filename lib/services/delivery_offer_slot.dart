import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stacked_services/stacked_services.dart';

/// En qué está la oferta de la banda.
enum OfferSlotState {
  /// No hay oferta en la banda.
  empty,

  /// Esperando que el chofer decida (o que venza).
  pending,

  /// El chofer ya decidió y la respuesta está en vuelo (aceptando en el back):
  /// nadie más puede contestar esta oferta.
  responding,
}

/// Lugar para la oferta de pedido mientras el chofer está en el final de una
/// entrega (QR de entrega o cobro).
///
/// Con esas pantallas arriba, la oferta a pantalla completa las taparía.
/// Mientras alguna la hospeda ([host]), la oferta se muestra como una banda
/// dentro de esa pantalla y se contesta con [respond], con la misma respuesta
/// que daría el diálogo. Cada oferta tiene UNA sola respuesta: cuando el chofer
/// decide ([beginResponse]) la oferta queda tomada y ni otra interfaz ni el
/// cierre de la pantalla pueden contestarla. Si las pantallas se cierran con la
/// oferta todavía sin decidir ([release]), sigue a pantalla completa en lo que
/// quede abajo, sin perder su cuenta regresiva.
class DeliveryOfferSlot extends ChangeNotifier {
  int _hosts = 0;
  Map<String, dynamic>? _offer;
  OfferSlotState _state = OfferSlotState.empty;
  Completer<DialogResponse<dynamic>?>? _pending;
  Future<DialogResponse<dynamic>?> Function()? _fullScreen;

  /// Hay una pantalla del final de la entrega arriba que recibe la oferta.
  bool get hosting => _hosts > 0;

  OfferSlotState get state => _state;

  /// Oferta en la banda (payload del socket), mientras no se respondió.
  Map<String, dynamic>? get offer => _offer;

  String? _notice;

  /// Aviso que se muestra en la banda sin bloquear la pantalla (por ejemplo,
  /// «aceptaste un pedido más»). Se va cuando no queda pantalla que lo hospede.
  String? get notice => _notice;

  /// Muestra [text] en la pantalla que hospeda, sin taparla. Devuelve false si
  /// no hay ninguna: el que avisa lo hace por su cuenta.
  bool announce(String text) {
    if (!hosting) return false;
    _notice = text;
    notifyListeners();
    return true;
  }

  /// Muestra la oferta: en la banda si hay una pantalla que la hospede; si no,
  /// con [fullScreen] (el diálogo de siempre). Devuelve la respuesta del chofer.
  ///
  /// Una sola oferta a la vez: si ya hay una en la banda, la nueva se rechaza
  /// explícitamente (`confirmed: false`) y la que estaba sigue.
  Future<DialogResponse<dynamic>?> show(
    Map<String, dynamic> offer,
    Future<DialogResponse<dynamic>?> Function() fullScreen,
  ) {
    if (!hosting) return fullScreen();
    if (_state != OfferSlotState.empty) {
      return Future.value(DialogResponse(confirmed: false));
    }
    final c = Completer<DialogResponse<dynamic>?>();
    _pending = c;
    _offer = offer;
    _fullScreen = fullScreen;
    _state = OfferSlotState.pending;
    notifyListeners();
    return c.future;
  }

  /// El chofer decidió sobre [offer] y la respuesta va a tardar (aceptar en el
  /// back). Devuelve false si esa oferta ya no está para decidir (otra
  /// respuesta la tomó, o ya no es la de la banda): quien llama no sigue.
  bool beginResponse(Map<String, dynamic> offer) {
    if (_state != OfferSlotState.pending || !identical(offer, _offer)) {
      return false;
    }
    _state = OfferSlotState.responding;
    notifyListeners();
    return true;
  }

  /// La respuesta a [offer] (rechazo, vencimiento o el resultado de aceptar).
  /// Vale una sola vez por oferta; si [offer] ya no es la de la banda, se
  /// ignora.
  void respond(Map<String, dynamic> offer, DialogResponse<dynamic> response) {
    final c = _pending;
    if (c == null || !identical(offer, _offer)) return;
    _clear();
    c.complete(response);
    notifyListeners();
  }

  void host() => _hosts++;

  /// Una pantalla que hospedaba se cerró. Si no queda ninguna, el aviso se va
  /// y una oferta TODAVÍA SIN DECIDIR pasa a pantalla completa. Si la respuesta
  /// está en vuelo, se espera esa respuesta: no se abre otra interfaz.
  void release() {
    if (_hosts > 0) _hosts--;
    if (hosting) return;
    _notice = null;
    final c = _pending;
    final full = _fullScreen;
    if (_state != OfferSlotState.pending || c == null || full == null) {
      notifyListeners();
      return;
    }
    _clear();
    c.complete(full());
    notifyListeners();
  }

  void _clear() {
    _pending = null;
    _offer = null;
    _fullScreen = null;
    _state = OfferSlotState.empty;
  }
}
