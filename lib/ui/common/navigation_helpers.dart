import 'package:flutter/widgets.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:splg_driver/app/app.router.dart';

/// Observador de rutas de la app: las vistas que necesitan saber si están al
/// frente (el Inicio, para pausar sus consultas) se suscriben acá.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Vuelve a la primera ruta del stack (el Inicio), cerrando todo lo que hay
/// encima. A diferencia de `clearStackAndShow`, el Inicio que ya estaba sigue
/// vivo: conserva el socket, la búsqueda de pedidos y el seguimiento de GPS.
void popToHome() =>
    StackedService.navigatorKey?.currentState?.popUntil((r) => r.isFirst);

/// Reemplaza la pantalla actual por el cobro de [orderId] y confirma que quedó
/// arriba. `replaceWith` puede no navegar sin avisar (sin navegador, o un
/// duplicado bloqueado) y su futuro recién termina cuando el cobro se cierra:
/// lo que vale es la ruta actual justo después (el observador de rutas la
/// actualiza en el momento). Si el cobro ya estaba arriba también cuenta.
bool openPaymentView(NavigationService nav, String orderId) {
  final opening = nav.replaceWithPaymentView(orderId: orderId);
  // Un error de la navegación no queda sin atender: se registra y la ruta
  // actual dice si se abrió.
  opening.then((_) {}, onError: (Object e) {
    debugPrint('No se pudo abrir el cobro de $orderId: $e');
  });
  return nav.currentRoute == Routes.paymentView;
}
