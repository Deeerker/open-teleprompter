import Foundation
import Observation

/// The script, its display settings and the scroll position. Everything stays on the device.
@MainActor
@Observable
final class Prompter {
    static let fontSizeRange: ClosedRange<Double> = 20...64
    static let speedRange: ClosedRange<Double> = 10...150

    private enum Key {
        static let text = "prompterText"
        static let fontSize = "prompterFontSize"
        static let speed = "prompterSpeed"
    }

    static let sampleText = """
    Toca este recuadro para escribir o pegar tu texto.

    Cuando empieces a grabar, el texto va a subir solo. Ajusta la velocidad con la tortuga y la liebre, y el tamaño con los botones de letra.

    Mientras grabas, toca el texto para pausarlo y arrástralo para avanzar o retroceder.

    El video se guarda solo en Fotos al terminar.
    """

    var text: String {
        didSet { UserDefaults.standard.set(text, forKey: Key.text) }
    }

    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Key.fontSize) }
    }

    /// Points per second.
    var speed: Double {
        didSet {
            // Keep the text where it is when the speed changes mid-scroll.
            if let playingSince {
                baseOffset = clamp(baseOffset + Date.now.timeIntervalSince(playingSince) * oldValue)
                self.playingSince = .now
            }
            UserDefaults.standard.set(speed, forKey: Key.speed)
        }
    }

    private(set) var isPlaying = false
    /// Largest scroll offset; the view sets it from the measured text height.
    var maxOffset: Double = 0

    private var baseOffset: Double = 0
    private var playingSince: Date?
    private var dragStartOffset: Double?
    private var resumeAfterDrag = false

    init() {
        let defaults = UserDefaults.standard
        text = defaults.string(forKey: Key.text) ?? Self.sampleText
        let savedSize = defaults.double(forKey: Key.fontSize)
        fontSize = savedSize > 0 ? savedSize : 32
        let savedSpeed = defaults.double(forKey: Key.speed)
        speed = savedSpeed > 0 ? savedSpeed : 45
    }

    func offset(at date: Date) -> Double {
        var value = baseOffset
        if let playingSince {
            value += max(0, date.timeIntervalSince(playingSince)) * speed
        }
        return clamp(value)
    }

    func play() {
        guard !isPlaying else { return }
        playingSince = .now
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        baseOffset = offset(at: .now)
        playingSince = nil
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func rewind() {
        playingSince = nil
        isPlaying = false
        baseOffset = 0
    }

    func drag(translation: Double) {
        if dragStartOffset == nil {
            resumeAfterDrag = isPlaying
            pause()
            dragStartOffset = baseOffset
        }
        baseOffset = clamp((dragStartOffset ?? 0) - translation)
    }

    func endDrag() {
        dragStartOffset = nil
        if resumeAfterDrag {
            play()
        }
        resumeAfterDrag = false
    }

    func changeFontSize(by delta: Double) {
        fontSize = min(max(fontSize + delta, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), maxOffset)
    }
}
