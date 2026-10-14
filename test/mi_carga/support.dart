import 'package:dio/dio.dart';
import 'package:splg_driver/models/truck_load.dart';

/// `GET /truck-loads/mine` con la forma de `MyTruckLoadDto` (el tipo de
/// garrafa viene con la palabra, como en el resto del back: "Garrafa 25kg").
Map<String, dynamic> myLoadJson({bool open = true, bool require = true}) => {
      'requireOpenTruckLoad': require,
      'load': open
          ? {
              'loadId': 'l1',
              'number': 12,
              'status': 'on_route',
              'businessDate': '2026-10-12',
              'carId': 'c1',
              'carPatent': 'AB123CD',
              'deliveryId': 'd1',
              'driverName': 'Pedro Gómez',
              'helperEmployeeId': null,
              'helperName': null,
              'originWarehouseId': 'w1',
              'originName': 'Depósito central',
              'openedAt': '2026-10-12T11:00:00.000Z',
              'departedAt': '2026-10-12T12:30:00.000Z',
              'returnedAt': null,
              'closedAt': null,
              'itemsCount': 1,
              'differenceNote': null,
              'cancelReason': null,
              'notes': null,
              'openedByUserId': 'u9',
              'orders': [],
              'cash': {
                'deliveredOrders': 0,
                'cashCollectedAmount': 0,
                'cashCollectedCount': 0,
                'unpaidAmount': 0,
                'unpaidCount': 0,
                'pendingConfirmationAmount': 0,
                'pendingConfirmationCount': 0,
                'nonCashAmount': 0,
              },
              'movements': [],
              'createdAt': '2026-10-12T10:55:00.000Z',
              'items': [
                {
                  'itemId': 'i1',
                  'gasCylinderId': 'g1',
                  'gasCylinderType': 'Garrafa 25kg',
                  'loadedFull': 40,
                  'reloadedFull': 0,
                  'loadedEmpty': 10,
                  'deliveredFull': 30,
                  'collectedEmpty': 28,
                  'expectedFull': 10,
                  'expectedEmpty': 38,
                  'declaredReturnFull': null,
                  'declaredReturnEmpty': null,
                  'differenceFull': null,
                  'differenceEmpty': null,
                  'onTruckFull': 10,
                  'onTruckEmpty': 38,
                }
              ],
            }
          : null,
    };

MyTruckLoad myLoad({bool open = true, bool require = true}) =>
    MyTruckLoad.fromJson(myLoadJson(open: open, require: require));

/// `GET /orders/available` de un chofer que no puede recibir pedidos por su
/// carga (`AvailableOrdersResponseDto`).
Map<String, dynamic> availableBlocked(String message) => {
      'orders': [],
      'total': 0,
      'limit': 1,
      'offset': 0,
      'openLoadRequired': true,
      'message': message,
    };

const kMsgSinCarga = 'Abrí tu carga para recibir pedidos';
const kMsgSinSalir =
    'La carga N° 12 todavía no salió: confirmá la salida del camión para recibir pedidos';
const kMsgDevuelta =
    'La carga N° 12 ya volvió: no se reciben pedidos hasta cerrar su rendición';

/// Error del back con la forma real del 422 de idempotencia.
DioException idempotency422() => DioException(
    requestOptions: RequestOptions(path: ''),
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 422,
        data: {
          'statusCode': 422,
          'message':
              'Esa clave de idempotencia ya se usó con otros datos. Revisá si la operación anterior se registró antes de reintentar.',
          'error': 'Unprocessable Entity',
        }));
