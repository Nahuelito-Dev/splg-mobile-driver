# splg-app-chofer

App del **chofer**: se pone en línea, recibe ofertas de despacho, entrega y cobra.
Flutter + Stacked, comparte código con `../splg-lib` (dependencia por `path`).
Mapa del sistema y reglas del workspace: `../AGENTS.md`.

<!-- orq:gate: flutter analyze --no-fatal-infos && flutter test -->

## Comandos

| Para | Comando |
|---|---|
| Gate | `flutter analyze --no-fatal-infos && flutter test` (warnings y errores cortan) |
| Correr contra el back local | `flutter run --dart-define=API_BASE_URL=http://<ip-de-la-mac>:3000` |
| Regenerar Stacked (rutas, locator) | `dart run build_runner build --delete-conflicting-outputs` |
| Actualizar goldens (sólo si el cambio visual es intencional) | `flutter test --update-goldens` |

La configuración entra por `--dart-define` (`lib/core/config/app_config.dart`): `API_BASE_URL`,
slug de distribuidora y URLs de retorno de Mercado Pago. Nunca hardcodear URLs ni claves.

## Reglas

- Arquitectura Stacked: la vista no tiene lógica; el ViewModel habla con services; los
  services, con la API. Lo que usan las dos apps va a `splg-lib`.
- Cambio en `splg-lib` ⇒ correr el gate de la lib **y** el de las dos apps.
- El contrato lo define el back (`../splg-app-backend`, `/docs-json`). Un 4xx del back se
  muestra; nunca se asume éxito (ej.: ponerse en línea con 403).
- Sistema visual Brasa, igual que el panel.
- Probado en emulador contra el back corriendo antes de darlo por hecho.
