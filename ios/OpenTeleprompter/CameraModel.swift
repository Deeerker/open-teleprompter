import AVFoundation
import Photos
import UIKit

enum CameraAlert: Identifiable {
    case photosDenied
    case recordingFailed
    case saveFailed

    var id: Self { self }

    var title: String {
        switch self {
        case .photosDenied: "Permite guardar en Fotos"
        case .recordingFailed: "No se pudo grabar"
        case .saveFailed: "No se pudo guardar el video"
        }
    }

    var message: String {
        switch self {
        case .photosDenied:
            "Los videos se guardan en Fotos apenas terminas de grabar. Activa “Fotos” en Ajustes para poder grabar."
        case .recordingFailed:
            "Vuelve a intentarlo."
        case .saveFailed:
            "Revisa que tengas espacio disponible y que la app pueda agregar fotos en Ajustes."
        }
    }
}

@MainActor
@Observable
final class CameraModel {
    enum Status {
        case starting
        case running
        case needsPermission
        case unavailable
    }

    private(set) var status: Status = .starting
    private(set) var info: CameraInfo?
    private(set) var displayZoom: CGFloat = 1
    private(set) var isRecording = false
    private(set) var recordingStartedAt: Date?
    private(set) var torchOn = false
    private(set) var isSwitchingCamera = false
    private(set) var lastThumbnail: UIImage?
    /// Changes every time the video input changes, so the preview can update its rotation.
    private(set) var configurationID = 0
    var alert: CameraAlert?

    let prompter = Prompter()
    @ObservationIgnored let controller = CameraController()
    @ObservationIgnored private var didSetUp = false

    private static let positionKey = "cameraPosition"

    func setUp() async {
        guard !didSetUp else { return }
        didSetUp = true

        let camera = await AVCaptureDevice.requestAccess(for: .video)
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard camera, microphone else {
            status = .needsPermission
            return
        }

        controller.onZoomChange = { zoom in
            Task { @MainActor in self.displayZoom = zoom }
        }
        controller.onRecordingStarted = {
            Task { @MainActor in self.recordingDidStart() }
        }
        controller.onRecordingFinished = { result in
            Task { @MainActor in self.recordingDidFinish(result) }
        }

        // Front camera by default: a teleprompter is mostly used facing yourself.
        let saved = UserDefaults.standard.object(forKey: Self.positionKey) as? Int
        let position = saved.flatMap(AVCaptureDevice.Position.init(rawValue:)) ?? .front
        guard let info = await controller.start(position: position) else {
            status = .unavailable
            return
        }
        self.info = info
        configurationID += 1
        status = .running
    }

    // MARK: Recording

    func toggleRecording() {
        guard status == .running, !isSwitchingCamera else { return }
        if isRecording {
            controller.stopRecording()
            return
        }
        let photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard photos == .authorized || photos == .limited else {
            alert = .photosDenied
            return
        }
        isRecording = true
        controller.startRecording()
    }

    func appDidEnterBackground() {
        if isRecording {
            controller.stopRecording()
        }
    }

    private func recordingDidStart() {
        recordingStartedAt = .now
        prompter.play()
    }

    private func recordingDidFinish(_ result: Result<URL, any Error>) {
        isRecording = false
        recordingStartedAt = nil
        prompter.rewind()
        switch result {
        case .success(let url):
            Task { await save(url) }
        case .failure:
            alert = .recordingFailed
        }
    }

    private func save(_ url: URL) async {
        if let thumbnail = await Self.thumbnail(for: url) {
            lastThumbnail = thumbnail
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: options)
            }
        } catch {
            alert = .saveFailed
        }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static func thumbnail(for url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: Camera controls

    func flipCamera() async {
        guard let info, !isRecording, !isSwitchingCamera else { return }
        isSwitchingCamera = true
        let target: AVCaptureDevice.Position = info.position == .back ? .front : .back
        if let newInfo = await controller.switchCamera(to: target) {
            self.info = newInfo
            torchOn = false
            configurationID += 1
            UserDefaults.standard.set(target.rawValue, forKey: Self.positionKey)
        }
        isSwitchingCamera = false
    }

    func toggleTorch() {
        guard info?.hasTorch == true else { return }
        torchOn.toggle()
        controller.setTorch(torchOn)
    }

    func focus(at devicePoint: CGPoint) {
        controller.focus(at: devicePoint)
    }

    func zoom(to preset: CGFloat) {
        controller.zoom(to: preset)
    }

    func beginPinch() {
        controller.beginPinch()
    }

    func pinch(scale: CGFloat) {
        controller.pinch(scale: scale)
    }

    #if DEBUG
    private(set) var isScreenshotMode = false

    func startScreenshotMode(_ shot: String) async {
        isScreenshotMode = true
        prompter.text = ScreenshotMode.script
        prompter.fontSize = 32
        prompter.speed = 20
        info = CameraInfo(position: .back, zoomPresets: [0.5, 1, 3], hasTorch: true)
        status = .running
        guard shot == "recording" else { return }
        // Wait for the text to be measured, then show it mid-scroll with the timer running.
        try? await Task.sleep(for: .milliseconds(600))
        prompter.drag(translation: -150)
        prompter.endDrag()
        isRecording = true
        recordingStartedAt = Date.now.addingTimeInterval(-14)
        prompter.play()
    }
    #endif
}
