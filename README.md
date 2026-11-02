# Open Teleprompter

App gratis y de código abierto para iPhone. Graba video como la app Cámara, con tu texto encima: el texto sube solo mientras grabas y el video se guarda automáticamente en Fotos. No usa internet ni recopila datos ([PRIVACY.md](PRIVACY.md)).

Sitio: [urcalab.com/teleprompter](https://urcalab.com/teleprompter/)

## Uso

- Toca el recuadro de texto (o el lápiz) para escribir o pegar el guion.
- Ajusta tamaño de letra y velocidad con los controles bajo el texto.
- Graba con el botón rojo, los botones de volumen o el Control de Cámara.
- Mientras grabas: toca el texto para pausarlo y arrástralo para avanzar o retroceder.
- Igual que en Cámara: toca para enfocar, pellizca para hacer zoom, botones 0,5× / 1× / 2-5× en la cámara trasera, linterna y cambio de cámara.

## Desarrollo

- `ios/OpenTeleprompter.xcodeproj`, SwiftUI + AVFoundation, iOS 17+, Swift 6, sin dependencias.
- Equipo de Apple: Urcalab (`37AKWW8NZ2`), bundle ID `cl.urcalab.openteleprompter`.
- Los videos se graban en vertical, 9:16, HEVC, con el preset `.high` (1080p).

```bash
cd ios
xcodebuild -project OpenTeleprompter.xcodeproj -scheme OpenTeleprompter -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

## Licencia

MIT. Ver [LICENSE](LICENSE).
