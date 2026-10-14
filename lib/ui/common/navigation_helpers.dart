import 'package:flutter/widgets.dart';
import 'package:stacked_services/stacked_services.dart';

/// Observador de rutas de la app: las vistas que necesitan saber si están al
/// frente (el Inicio, para pausar sus consultas) se suscriben acá.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Vuelve a la primera ruta del stack (el Inicio), cerrando todo lo que hay
/// encima. A diferencia de `clearStackAndShow`, el Inicio que ya estaba sigue
/// vivo: conserva el socket, la búsqueda de pedidos y el seguimiento de GPS.
void popToHome() =>
    StackedService.navigatorKey?.currentState?.popUntil((r) => r.isFirst);
