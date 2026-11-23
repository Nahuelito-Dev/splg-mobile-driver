import 'package:splg_driver/services/location_service.dart';

/// Con permiso y GPS prendido: la última posición del stream si tiene entre 0 y
/// [maxAge] (una con hora futura no cuenta como fresca); si no, una lectura
/// nueva del GPS. Sin permiso o con el GPS apagado no se usa ni la posición
/// guardada. Si el permiso se puede volver a pedir, se pide; si lo dan, se lee
/// el GPS de nuevo. [isCancelled] corta si la pantalla se cerró mientras tanto.
Future<PositionRead> readCurrentPosition(
  LocationService location, {
  required Duration maxAge,
  required Duration timeout,
  required DateTime Function() clock,
  bool Function()? isCancelled,
}) async {
  final block = await location.locationBlock();
  if (block == LocationBlock.permissionDenied) {
    await location.requestLocationPermission();
    if (isCancelled?.call() ?? false) {
      return const PositionRead.blocked(LocationBlock.permissionDenied);
    }
    final after = await location.locationBlock();
    if (after != null) return PositionRead.blocked(after);
    return location.readFreshPosition(timeout: timeout);
  }
  if (block != null) return PositionRead.blocked(block);
  final last = location.currentPosition;
  if (last != null) {
    final age = clock().difference(last.timestamp);
    if (!age.isNegative && age <= maxAge) return PositionRead.ok(last);
  }
  return location.readFreshPosition(timeout: timeout);
}
