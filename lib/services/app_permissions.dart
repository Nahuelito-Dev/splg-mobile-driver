import 'package:splg_lib/permissions/app_permission.dart';
import 'package:splg_lib/permissions/permission_copy.dart';
import 'package:splg_lib/permissions/permission_gateway.dart';
import 'package:splg_lib/permissions/permission_prompter.dart';
import 'package:splg_lib/permissions/permissions_service.dart';
import 'package:stacked_services/stacked_services.dart';

/// Permisos de la app chofer: cada uno se pide en el momento en que hace falta (ver
/// los llamados), con una explicación previa y con camino a Ajustes si queda
/// denegado para siempre. Los textos específicos de la app están acá.
class AppPermissions extends PermissionsService {
  AppPermissions()
      : super(
          gateway: const PermissionHandlerGateway(),
          prompter: NavigatorPermissionPrompter(StackedService.navigatorKey),
          copy: _copy,
        );

  static const Map<AppPermission, PermissionCopy> _copy = {
    AppPermission.location: PermissionCopy(
      title: 'Ubicación',
      rationale:
          'SPLG usa tu ubicación mientras estás en línea para asignarte pedidos cercanos y compartir tu posición con el cliente durante la entrega.',
      deniedMessage:
          'Sin la ubicación no podemos asignarte pedidos cercanos. Podés volver a intentarlo.',
      settingsMessage:
          'La ubicación está desactivada para SPLG. Activala desde Ajustes para ponerte en línea y recibir pedidos.',
    ),
    AppPermission.camera: PermissionCopy(
      title: 'Cámara',
      rationale:
          'SPLG usa la cámara para que puedas sacar una foto cuando reportás una incidencia en una entrega.',
      deniedMessage:
          'Sin la cámara no podemos adjuntar la foto de la incidencia. Podés volver a intentarlo.',
      settingsMessage:
          'La cámara está desactivada para SPLG. Activala desde Ajustes para adjuntar fotos.',
    ),
    AppPermission.notifications: PermissionCopy(
      title: 'Notificaciones',
      rationale:
          'SPLG te avisa por notificación cuando hay un pedido nuevo para vos y mantiene el aviso de que estás en línea.',
      deniedMessage:
          'Sin notificaciones podés perderte ofertas de pedido con la app cerrada. Igual podés seguir usando la app.',
      settingsMessage:
          'Las notificaciones están desactivadas para SPLG. Activalas desde Ajustes para no perderte pedidos.',
    ),
  };
}
