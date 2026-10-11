import 'package:stacked_services/stacked_services.dart';

/// Vuelve a la primera ruta del stack (el Inicio), cerrando todo lo que hay
/// encima. A diferencia de `clearStackAndShow`, el Inicio que ya estaba sigue
/// vivo: conserva el socket, la búsqueda de pedidos y el seguimiento de GPS.
void popToHome() =>
    StackedService.navigatorKey?.currentState?.popUntil((r) => r.isFirst);
