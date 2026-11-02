import SwiftUI

struct CameraScreen: View {
    @State private var model = CameraModel()
    @State private var showEditor = false
    @State private var focusPoint: CGPoint?
    @State private var focusID = 0
    @State private var flipTurns = 0.0
    @AppStorage("showPrompter") private var showPrompter = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.status {
            case .starting, .running:
                camera
            case .needsPermission:
                MessageView(
                    systemImage: "video.slash",
                    text: "Para grabar, permite el acceso a la cámara y al micrófono en Ajustes.",
                    action: ("Abrir Ajustes", openSettings)
                )
            case .unavailable:
                MessageView(systemImage: "video.slash", text: "No se encontró una cámara disponible.", action: nil)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await model.setUp() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.appDidEnterBackground()
            }
        }
        .onChange(of: model.isRecording) { _, recording in
            UIApplication.shared.isIdleTimerDisabled = recording
        }
        .sheet(isPresented: $showEditor) {
            ScriptEditor(prompter: model.prompter)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { alert in
            if alert == .photosDenied {
                Button("Abrir Ajustes", action: openSettings)
                Button("Cancelar", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: Camera

    private var camera: some View {
        GeometryReader { screen in
            ZStack {
                preview
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    if showPrompter {
                        PrompterOverlay(
                            prompter: model.prompter,
                            isRecording: model.isRecording,
                            height: max(140, screen.size.height * 0.3),
                            onEdit: { showEditor = true }
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    bottomControls
                }
                .animation(.easeInOut(duration: 0.2), value: showPrompter)
            }
        }
    }

    /// 9:16 like the recorded video, so what you see is exactly what gets saved.
    private var preview: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = min(geometry.size.height, width * 16 / 9)
            CameraPreview(
                session: model.controller.session,
                configurationID: model.configurationID,
                onFocus: { viewPoint, devicePoint in
                    model.focus(at: devicePoint)
                    focusPoint = viewPoint
                    focusID += 1
                },
                onPinchBegan: model.beginPinch,
                onPinch: model.pinch(scale:),
                onHardwareButton: model.toggleRecording
            )
            .overlay {
                if let focusPoint {
                    FocusSquare()
                        .id(focusID)
                        .position(focusPoint)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
            .position(x: width / 2, y: geometry.size.height / 2)
        }
        .task(id: focusID) {
            guard focusPoint != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { focusPoint = nil }
        }
    }

    private var topBar: some View {
        HStack {
            if model.info?.hasTorch == true {
                CircleButton(
                    systemImage: model.torchOn ? "bolt.fill" : "bolt.slash.fill",
                    tint: model.torchOn ? .yellow : .white,
                    label: model.torchOn ? "Apagar luz" : "Encender luz",
                    action: model.toggleTorch
                )
            } else {
                Color.clear.frame(width: 38, height: 38)
            }

            Spacer()

            if model.isRecording {
                RecordingTimer(start: model.recordingStartedAt)
            }

            Spacer()

            CircleButton(
                systemImage: "text.alignleft",
                tint: showPrompter ? .yellow : .white,
                label: showPrompter ? "Ocultar texto" : "Mostrar texto",
                action: { showPrompter.toggle() }
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            if let presets = model.info?.zoomPresets, presets.count > 1 {
                ZoomPicker(presets: presets, current: model.displayZoom, select: model.zoom(to:))
            }

            Text("VIDEO")
                .font(.system(size: 14, weight: .semibold))
                .kerning(1)
                .foregroundStyle(.yellow)
                .opacity(model.isRecording ? 0 : 1)

            HStack {
                thumbnail
                Spacer()
                RecordButton(isRecording: model.isRecording, action: model.toggleRecording)
                    .disabled(model.status != .running)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { flipTurns += 0.5 }
                    Task { await model.flipCamera() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(flipTurns * 360))
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.15), in: .circle)
                }
                .accessibilityLabel("Cambiar de cámara")
                .opacity(model.isRecording ? 0 : 1)
                .disabled(model.isRecording || model.isSwitchingCamera)
            }
            .padding(.horizontal, 30)
        }
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.2), value: model.isRecording)
    }

    private var thumbnail: some View {
        Button {
            if let url = URL(string: "photos-redirect://") {
                openURL(url)
            }
        } label: {
            Group {
                if let image = model.lastThumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 1))
        }
        .accessibilityLabel("Abrir Fotos")
        .opacity(model.isRecording ? 0 : 1)
        .disabled(model.isRecording)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

// MARK: - Controls

private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: isRecording ? 7 : 32)
                    .fill(.red)
                    .frame(width: isRecording ? 32 : 64, height: isRecording ? 32 : 64)
            }
            .animation(.spring(duration: 0.3), value: isRecording)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isRecording)
        .accessibilityLabel(isRecording ? "Detener grabación" : "Grabar")
    }
}

private struct CircleButton: View {
    let systemImage: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.35), in: .circle)
        }
        .accessibilityLabel(label)
    }
}

private struct ZoomPicker: View {
    let presets: [CGFloat]
    let current: CGFloat
    let select: (CGFloat) -> Void

    /// The preset closest below the current zoom shows the live value, like the Camera app.
    private var activeIndex: Int {
        presets.lastIndex(where: { current >= $0 - 0.01 }) ?? 0
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                let active = index == activeIndex
                Button { select(preset) } label: {
                    Text(active ? Self.format(current, suffix: true) : Self.format(preset, suffix: false))
                        .font(.system(size: active ? 13 : 12, weight: .bold))
                        .foregroundStyle(active ? .yellow : .white)
                        .frame(width: active ? 38 : 30, height: active ? 38 : 30)
                        .background(.black.opacity(0.45), in: .circle)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Zoom \(Self.format(preset, suffix: true))")
            }
        }
        .padding(3)
        .background(.black.opacity(0.25), in: .capsule)
        .animation(.easeInOut(duration: 0.15), value: activeIndex)
    }

    private static func format(_ value: CGFloat, suffix: Bool) -> String {
        let rounded = (Double(value) * 10).rounded() / 10
        var text = rounded.formatted(.number.precision(.fractionLength(0...1)))
        if rounded < 1, let range = text.range(of: "0") {
            text.removeSubrange(range)
        }
        return suffix ? text + "×" : text
    }
}

private struct RecordingTimer: View {
    let start: Date?

    var body: some View {
        TimelineView(.periodic(from: start ?? .now, by: 1)) { context in
            Text(Self.format(start.map { context.date.timeIntervalSince($0) } ?? 0))
                .font(.system(size: 17, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.red, in: .rect(cornerRadius: 6))
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

private struct FocusSquare: View {
    @State private var settled = false

    var body: some View {
        Rectangle()
            .stroke(.yellow, lineWidth: 1.5)
            .frame(width: 76, height: 76)
            .scaleEffect(settled ? 1 : 1.35)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { settled = true }
            }
    }
}

private struct MessageView: View {
    let systemImage: String
    let text: String
    let action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
            }
        }
        .padding(32)
    }
}
