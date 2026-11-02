import AVFoundation
import AVKit
import SwiftUI

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    func applyPortraitRotation() {
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

/// Live camera feed with the Camera app gestures: tap to focus, pinch to zoom,
/// and the volume buttons (or Camera Control) to start and stop recording.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let configurationID: Int
    var onFocus: (_ viewPoint: CGPoint, _ devicePoint: CGPoint) -> Void
    var onPinchBegan: () -> Void
    var onPinch: (CGFloat) -> Void
    var onHardwareButton: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pinch)

        if #available(iOS 17.2, *) {
            let coordinator = context.coordinator
            let interaction = AVCaptureEventInteraction { event in
                if event.phase == .ended {
                    coordinator.parent.onHardwareButton()
                }
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.parent = self
        view.applyPortraitRotation()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: CameraPreview

        init(parent: CameraPreview) {
            self.parent = parent
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewView else { return }
            let point = gesture.location(in: view)
            parent.onFocus(point, view.previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.onPinchBegan()
            case .changed:
                parent.onPinch(gesture.scale)
            default:
                break
            }
        }
    }
}
