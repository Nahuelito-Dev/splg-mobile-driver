// Carga del camión tal como la ve el chofer: `GET /truck-loads/mine` y las
// respuestas de la salida y el regreso del camión.
// Es tolerante: lo que falte queda en cero o null, nunca rompe.

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

int _int(Object? v) =>
    v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

int? _intOrNull(Object? v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');

/// Estados de una carga (`TruckLoadStatus` del back).
enum TruckLoadStatus {
  loading('En carga'),
  onRoute('En ruta'),
  returned('Devuelta'),
  closed('Cerrada'),
  closedWithDifference('Cerrada con diferencia'),
  cancelled('Cancelada');

  const TruckLoadStatus(this.label);

  final String label;

  static TruckLoadStatus parse(String? raw) => switch (raw) {
        'on_route' => onRoute,
        'returned' => returned,
        'closed' => closed,
        'closed_with_difference' => closedWithDifference,
        'cancelled' => cancelled,
        _ => loading,
      };
}

/// Un renglón de la carga: un tipo de garrafa.
class TruckLoadItem {
  const TruckLoadItem({
    this.gasCylinderId = '',
    required this.type,
    required this.loadedFull,
    required this.loadedEmpty,
    required this.reloadedFull,
    required this.deliveredFull,
    required this.collectedEmpty,
    required this.expectedFull,
    required this.expectedEmpty,
    this.declaredReturnFull,
    this.declaredReturnEmpty,
  });

  /// Id de la garrafa: con él se declara lo que vuelve.
  final String gasCylinderId;

  /// Tal como lo trae el back: "Garrafa 10kg".
  final String type;
  final int loadedFull;

  /// Vacías con las que salió el camión.
  final int loadedEmpty;
  final int reloadedFull;
  final int deliveredFull;
  final int collectedEmpty;

  /// Llenas que quedan: cargadas + repuestas - entregadas.
  final int expectedFull;

  /// Vacías que debería llevar: cargadas + recolectadas.
  final int expectedEmpty;

  /// Lo que el chofer declaró que vuelve (null mientras no declaró).
  final int? declaredReturnFull;
  final int? declaredReturnEmpty;

  factory TruckLoadItem.fromJson(Map<String, dynamic> json) => TruckLoadItem(
        gasCylinderId: _str(json['gasCylinderId']) ?? '',
        type: _str(json['gasCylinderType']) ?? 'Garrafa',
        loadedFull: _int(json['loadedFull']),
        loadedEmpty: _int(json['loadedEmpty']),
        reloadedFull: _int(json['reloadedFull']),
        deliveredFull: _int(json['deliveredFull']),
        collectedEmpty: _int(json['collectedEmpty']),
        expectedFull: _int(json['expectedFull']),
        expectedEmpty: _int(json['expectedEmpty']),
        declaredReturnFull: _intOrNull(json['declaredReturnFull']),
        declaredReturnEmpty: _intOrNull(json['declaredReturnEmpty']),
      );
}

/// Lo que vuelve de un tipo de garrafa (`DeclaredItemInputDto` de
/// `PATCH /truck-loads/:id/return`).
class ReturnDeclaration {
  const ReturnDeclaration({
    required this.gasCylinderId,
    required this.declaredFull,
    required this.declaredEmpty,
  });

  final String gasCylinderId;
  final int declaredFull;
  final int declaredEmpty;

  /// Tope por tipo que acepta el back (`MAX_POR_TIPO * 2`).
  static const int max = 4000;

  Map<String, dynamic> toJson() => {
        'gasCylinderId': gasCylinderId,
        'declaredFull': declaredFull,
        'declaredEmpty': declaredEmpty,
      };
}

class TruckLoad {
  const TruckLoad({
    required this.id,
    required this.number,
    required this.status,
    required this.carPatent,
    required this.originName,
    required this.openedAt,
    this.departedAt,
    this.returnedAt,
    this.helperName,
    this.items = const [],
  });

  final String id;
  final int number;
  final TruckLoadStatus status;
  final String? carPatent;
  final String originName;
  final DateTime? openedAt;
  final DateTime? departedAt;
  final DateTime? returnedAt;
  final String? helperName;
  final List<TruckLoadItem> items;

  /// El chofer puede confirmar la salida: la carga todavía está en el depósito
  /// y tiene garrafas.
  bool get canDepart => status == TruckLoadStatus.loading && items.isNotEmpty;

  /// El chofer puede declarar lo que vuelve; ya declarado, puede corregirlo
  /// hasta que la distribuidora cierre la carga.
  bool get canDeclareReturn =>
      status == TruckLoadStatus.onRoute || status == TruckLoadStatus.returned;

  factory TruckLoad.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return TruckLoad(
      id: _str(json['loadId']) ?? '',
      number: _int(json['number']),
      status: TruckLoadStatus.parse(_str(json['status'])),
      carPatent: _str(json['carPatent']),
      originName: _str(json['originName']) ?? 'Sin depósito',
      openedAt: DateTime.tryParse(_str(json['openedAt']) ?? '')?.toLocal(),
      departedAt: DateTime.tryParse(_str(json['departedAt']) ?? '')?.toLocal(),
      returnedAt: DateTime.tryParse(_str(json['returnedAt']) ?? '')?.toLocal(),
      helperName: _str(json['helperName']),
      items: items is List
          ? [
              for (final i in items.whereType<Map>())
                TruckLoadItem.fromJson(Map<String, dynamic>.from(i)),
            ]
          : const [],
    );
  }
}

/// Respuesta de `GET /truck-loads/mine`: la carga abierta del chofer (null si
/// no tiene) y si la distribuidora exige tener una para recibir pedidos (D5).
class MyTruckLoad {
  const MyTruckLoad({this.load, this.requireOpenTruckLoad = false});

  final TruckLoad? load;
  final bool requireOpenTruckLoad;

  factory MyTruckLoad.fromJson(Map<String, dynamic> json) {
    final load = json['load'];
    return MyTruckLoad(
      load: load is Map
          ? TruckLoad.fromJson(Map<String, dynamic>.from(load))
          : null,
      requireOpenTruckLoad: json['requireOpenTruckLoad'] == true,
    );
  }
}
