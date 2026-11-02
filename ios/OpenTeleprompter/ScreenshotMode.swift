#if DEBUG
import SwiftUI

/// App Store screenshots on the Simulator, which has no camera: the real UI over an out-of-focus
/// background instead of the camera feed. Debug builds only.
///
///   xcrun simctl launch <sim> cl.urcalab.openteleprompter -screenshot ready|recording|editor
enum ScreenshotMode {
    static var shot: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshot"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static let script = """
    Hola, soy Camila. Hoy te muestro tres trucos para que tus plantas de interior lleguen sanas a la primavera.

    Primero, riega menos. Con el frío la tierra tarda más en secarse, así que toca el sustrato antes de regar.

    Segundo, acércalas a la luz. Una ventana con sol de la mañana es ideal, pero sin que las hojas toquen el vidrio.

    Y tercero, aléjalas de la calefacción: el aire seco quema las puntas de las hojas.
    """
}

/// Stands in for the camera feed: a warm room, out of focus.
struct ScreenshotBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.33, green: 0.27, blue: 0.22), Color(red: 0.16, green: 0.13, blue: 0.11)],
                startPoint: .top,
                endPoint: .bottom
            )
            Group {
                Circle().fill(Color(red: 1.0, green: 0.78, blue: 0.48)).frame(width: 220).offset(x: -130, y: -260).opacity(0.55)
                Circle().fill(Color(red: 0.98, green: 0.85, blue: 0.62)).frame(width: 120).offset(x: 140, y: -330).opacity(0.5)
                Circle().fill(Color(red: 0.36, green: 0.52, blue: 0.30)).frame(width: 300).offset(x: 150, y: 120).opacity(0.6)
                Circle().fill(Color(red: 0.27, green: 0.42, blue: 0.24)).frame(width: 240).offset(x: -170, y: 260).opacity(0.55)
                // A person in front of the lens, out of focus.
                Ellipse().fill(Color(red: 0.55, green: 0.40, blue: 0.32)).frame(width: 190, height: 240).offset(y: 40)
                Ellipse().fill(Color(red: 0.20, green: 0.15, blue: 0.13)).frame(width: 220, height: 170).offset(y: -50)
                RoundedRectangle(cornerRadius: 140).fill(Color(red: 0.62, green: 0.70, blue: 0.78)).frame(width: 420, height: 360).offset(y: 380)
            }
            .blur(radius: 45)
        }
    }
}
#endif
