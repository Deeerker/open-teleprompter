# AGENTS.md

## Estructura

- `ios/` app iOS (SwiftUI + AVFoundation, sin dependencias). Ver el README.
- La página pública está en urcalab.com/teleprompter, en el repo `urcalab/wave` (`pages/urcalab/teleprompter/`).

## Reglas

- La app no se conecta a internet ni recopila datos. No agregar analítica, SDKs de terceros ni llamadas de red; si algo cambia lo que guarda la app, actualizar `PRIVACY.md`, la página de privacidad y `ios/OpenTeleprompter/PrivacyInfo.xcprivacy`.

## Commits

- Los cambios se commitean y se pushean directo a `main`, sin rama ni PR.
