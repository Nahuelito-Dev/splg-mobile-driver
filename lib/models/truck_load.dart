// Carga del camión tal como la ve el chofer: lectura de `GET /truck-loads/mine`.
// Es tolerante: lo que falte queda en cero o null, nunca rompe.

String? _str(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

int _int(Object? v) =>
    v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

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
    required this.type,
    required this.loadedFull,
    required this.loadedEmpty,
    required this.reloadedFull,
    required this.deliveredFull,
    required this.collectedEmpty,
    required this.expectedFull,
    required this.expectedEmpty,
  });

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

  factory TruckLoadItem.fromJson(Map<String, dynamic> json) => TruckLoadItem(
        type: _str(json['gasCylinderType']) ?? 'Garrafa',
        loadedFull: _int(json['loadedFull']),
        loadedEmpty: _int(json['loadedEmpty']),
        reloadedFull: _int(json['reloadedFull']),
        deliveredFull: _int(json['deliveredFull']),
        collectedEmpty: _int(json['collectedEmpty']),
        expectedFull: _int(json['expectedFull']),
        expectedEmpty: _int(json['expectedEmpty']),
      );
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
  final String? helperName;
  final List<TruckLoadItem> items;

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
