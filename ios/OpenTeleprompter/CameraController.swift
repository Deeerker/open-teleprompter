import AVFoundation

struct CameraInfo: Sendable {
    var position: AVCaptureDevice.Position
    /// Zoom presets as the Camera app shows them (1 = main wide lens, 0.5 = ultra wide).
    var zoomPresets: [CGFloat]
    var hasTorch: Bool
}

enum CameraError: Error {
    case notReady
}

/// Owns the AVCaptureSession. Every session and device access happens on `queue`.
final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    // Called on background queues. Set them before `start`.
    var onZoomChange: (@Sendable (CGFloat) -> Void)?
    var onRecordingStarted: (@Sendable () -> Void)?
    var onRecordingFinished: (@Sendable (Result<URL, any Error>) -> Void)?

    private let queue = DispatchQueue(label: "cl.urcalab.openteleprompter.camera")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    /// Device zoom factor that the UI shows as "1×".
    private var zoomBase: CGFloat = 1
    private var maxZoomFactor: CGFloat = 1
    private var pinchStartFactor: CGFloat = 1
    private var zoomObservation: NSKeyValueObservation?
    private var subjectAreaObserver: (any NSObjectProtocol)?

    // MARK: Session

    func start(position: AVCaptureDevice.Position) async -> CameraInfo? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                let info = self.installVideoInput(position: position)
                if let mic = AVCaptureDevice.default(for: .audio),
                   let input = try? AVCaptureDeviceInput(device: mic),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }
                self.configureMovieConnection()
                self.session.commitConfiguration()
                if info != nil {
                    self.session.startRunning()
                }
                continuation.resume(returning: info)
            }
        }
    }

    func switchCamera(to position: AVCaptureDevice.Position) async -> CameraInfo? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.beginConfiguration()
                let info = self.installVideoInput(position: position)
                self.configureMovieConnection()
                self.session.commitConfiguration()
                continuation.resume(returning: info)
            }
        }
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Virtual multi-lens devices switch lenses automatically while zooming, like the Camera app.
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        return nil
    }

    private func installVideoInput(position: AVCaptureDevice.Position) -> CameraInfo? {
        guard let device = Self.device(for: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        let previous = videoInput
        if let previous {
            session.removeInput(previous)
        }
        guard session.canAddInput(input) else {
            if let previous, session.canAddInput(previous) {
                session.addInput(previous)
            }
            return nil
        }
        session.addInput(input)
        videoInput = input
        return prepare(device)
    }

    private func configureMovieConnection() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        // The UI is portrait only, so videos are always recorded in portrait.
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        // Like the Camera app's default, front camera videos are saved unmirrored.
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        if movieOutput.availableVideoCodecTypes.contains(.hevc) {
            movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
        }
    }

    private func prepare(_ device: AVCaptureDevice) -> CameraInfo {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        let startsUltraWide = device.constituentDevices.first?.deviceType == .builtInUltraWideCamera
        let base = startsUltraWide ? (switchOvers.first ?? 1) : 1

        var presets: [CGFloat] = []
        if device.position == .back {
            if startsUltraWide {
                presets.append(1 / base)
            }
            presets.append(1)
            if let tele = switchOvers.first(where: { $0 > base }) {
                presets.append(tele / base)
            } else {
                presets.append(2)
            }
        }

        zoomBase = base
        maxZoomFactor = min(device.maxAvailableVideoZoomFactor, base * (device.position == .back ? 10 : 3))

        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = min(max(base, device.minAvailableVideoZoomFactor), maxZoomFactor)
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        }

        zoomObservation = device.observe(\.videoZoomFactor, options: [.initial, .new]) { [weak self] device, _ in
            self?.onZoomChange?(device.videoZoomFactor / base)
        }

        if let subjectAreaObserver {
            NotificationCenter.default.removeObserver(subjectAreaObserver)
        }
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.resetFocus() }
        }

        return CameraInfo(position: device.position, zoomPresets: presets, hasTorch: device.hasTorch)
    }

    private func withDevice(_ body: (AVCaptureDevice) -> Void) {
        guard let device = videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
        body(device)
        device.unlockForConfiguration()
    }

    // MARK: Focus

    /// `point` is in device coordinates (0...1), as returned by the preview layer.
    func focus(at point: CGPoint) {
        queue.async {
            self.withDevice { device in
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
            }
        }
    }

    private func resetFocus() {
        let center = CGPoint(x: 0.5, y: 0.5)
        withDevice { device in
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusPointOfInterest = center
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = center
                device.exposureMode = .continuousAutoExposure
            }
        }
    }

    // MARK: Zoom and torch

    func beginPinch() {
        queue.async {
            self.pinchStartFactor = self.videoInput?.device.videoZoomFactor ?? 1
        }
    }

    func pinch(scale: CGFloat) {
        queue.async {
            let target = self.clampZoom(self.pinchStartFactor * scale)
            self.withDevice { device in
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = target
            }
        }
    }

    /// `value` uses the UI scale (1 = main lens).
    func zoom(to value: CGFloat) {
        queue.async {
            let target = self.clampZoom(value * self.zoomBase)
            self.withDevice { $0.ramp(toVideoZoomFactor: target, withRate: 8) }
        }
    }

    private func clampZoom(_ factor: CGFloat) -> CGFloat {
        let minimum = videoInput?.device.minAvailableVideoZoomFactor ?? 1
        return min(max(factor, minimum), maxZoomFactor)
    }

    func setTorch(_ on: Bool) {
        queue.async {
            self.withDevice { device in
                guard device.hasTorch, device.isTorchModeSupported(on ? .on : .off) else { return }
                device.torchMode = on ? .on : .off
            }
        }
    }

    // MARK: Recording

    func startRecording() {
        queue.async {
            guard !self.movieOutput.isRecording else { return }
            guard self.session.isRunning, self.movieOutput.connection(with: .video)?.isActive == true else {
                self.onRecordingFinished?(.failure(CameraError.notReady))
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        queue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        onRecordingStarted?()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        // Interruptions (a call, going to the background) end the recording with an
        // error, but the file is still valid when this flag is set.
        if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
            try? FileManager.default.removeItem(at: outputFileURL)
            onRecordingFinished?(.failure(error))
        } else {
            onRecordingFinished?(.success(outputFileURL))
        }
    }
}
