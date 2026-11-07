import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/models/truck_load.dart';
import 'package:splg_driver/services/driver_api_service.dart';
import 'package:splg_driver/services/driver_ops_repository.dart';
import 'package:splg_driver/ui/common/load_view_model.dart';

/// Un tipo de garrafa en el formulario del regreso: lo que vuelve lleno y lo
/// que vuelve vacío.
class ReturnField {
  ReturnField(this.item, {required String full, required String empty})
      : full = TextEditingController(text: full),
        empty = TextEditingController(text: empty);

  final TruckLoadItem item;
  final TextEditingController full;
  final TextEditingController empty;
  String? fullError;
  String? emptyError;

  void dispose() {
    full.dispose();
    empty.dispose();
  }
}

/// Mi carga: la carga del camión abierta del chofer (`GET /truck-loads/mine`).
/// La abre y la cierra la distribuidora desde el panel; el chofer confirma la
/// salida del camión y declara lo que vuelve.
class MyLoadViewModel extends LoadViewModel {
  final _api = locator<DriverApiService>();
  DriverOpsRepository get _ops => locator<DriverOpsRepository>();

  MyTruckLoad? data;

  /// Motivo del último pull-to-refresh fallido (se sigue viendo lo anterior).
  String? refreshError;

  TruckLoad? get openLoad => data?.load;
  bool get requiresOpenLoad => data?.requireOpenTruckLoad ?? false;

  /// Salida o regreso en curso: los botones quedan cargando y un segundo toque
  /// no hace nada.
  bool acting = false;

  /// Por qué falló la confirmación de la salida (rechazo del back o sin red).
  String? actionError;

  /// Campos del formulario del regreso, uno por tipo de garrafa de la carga.
  List<ReturnField> returnFields = const [];

  /// Por qué el back rechazó la declaración del regreso.
  String? returnError;

  @override
  Future<void> fetch() async {
    data = await _api.myTruckLoad();
    refreshError = null;
  }

  /// Pull-to-refresh: relee sin tapar la pantalla con el indicador de carga.
  Future<void> refresh() async {
    try {
      await fetch();
      loadError = null;
    } catch (e) {
      refreshError = DriverApiService.errorMessage(e);
    }
    notifyListeners();
  }

  void _apply(TruckLoad load) {
    data = MyTruckLoad(
        load: load, requireOpenTruckLoad: data?.requireOpenTruckLoad ?? false);
    refreshError = null;
  }

  /// Un 409 dice que la carga está en otro estado (la distribuidora la cambió
  /// mientras tanto): se relee para mostrar la verdadera.
  Future<void> _resyncOnConflict(Object e) async {
    if (e is DioException && e.response?.statusCode == 409) await refresh();
  }

  /// Confirma la salida del camión (`PATCH /truck-loads/:id/depart`). La vista
  /// pide la confirmación antes. Devuelve `true` si el back la registró.
  Future<bool> depart() async {
    final load = openLoad;
    if (acting || load == null || !load.canDepart) return false;
    acting = true;
    actionError = null;
    notifyListeners();
    var ok = false;
    try {
      _apply(await _ops.departTruckLoad(load.id));
      ok = true;
    } catch (e) {
      actionError = actionErrorText(e);
      await _resyncOnConflict(e);
    }
    acting = false;
    notifyListeners();
    return ok;
  }

  /// Arma el formulario del regreso: parte de lo que ya declaró o, si todavía
  /// no declaró, de lo que el sistema espera que vuelva.
  void startReturn() {
    _disposeFields();
    returnError = null;
    returnFields = [
      for (final i in openLoad?.items ?? const <TruckLoadItem>[])
        ReturnField(i,
            full: '${i.declaredReturnFull ?? i.expectedFull}',
            empty: '${i.declaredReturnEmpty ?? i.expectedEmpty}'),
    ];
  }

  /// Entero entre 0 y [ReturnDeclaration.max], como pide el back.
  static String? validateCount(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Ingresá una cantidad.';
    final n = int.tryParse(t);
    if (n == null || n < 0) return 'Ingresá un número entero, 0 o más.';
    if (n > ReturnDeclaration.max) {
      return 'No puede pasar de ${ReturnDeclaration.max}.';
    }
    return null;
  }

  /// Declara lo que vuelve en el camión (`PATCH /truck-loads/:id/return`), de
  /// todas las garrafas de la carga. Devuelve `true` si el back lo registró.
  Future<bool> submitReturn() async {
    final load = openLoad;
    if (acting || load == null || !load.canDeclareReturn) return false;
    var valid = returnFields.isNotEmpty;
    for (final f in returnFields) {
      f.fullError = validateCount(f.full.text);
      f.emptyError = validateCount(f.empty.text);
      if (f.fullError != null || f.emptyError != null) valid = false;
    }
    returnError = null;
    if (!valid) {
      notifyListeners();
      return false;
    }
    acting = true;
    notifyListeners();
    var ok = false;
    try {
      _apply(await _ops.returnTruckLoad(load.id, [
        for (final f in returnFields)
          ReturnDeclaration(
            gasCylinderId: f.item.gasCylinderId,
            declaredFull: int.parse(f.full.text.trim()),
            declaredEmpty: int.parse(f.empty.text.trim()),
          ),
      ]));
      ok = true;
    } catch (e) {
      returnError = actionErrorText(e);
      await _resyncOnConflict(e);
    }
    acting = false;
    notifyListeners();
    return ok;
  }

  void _disposeFields() {
    for (final f in returnFields) {
      f.dispose();
    }
    returnFields = const [];
  }

  @override
  void dispose() {
    _disposeFields();
    super.dispose();
  }
}
