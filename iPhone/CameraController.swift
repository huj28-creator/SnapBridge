import AVFoundation
import UIKit
import Combine
import SwiftUI

struct CapturedPhoto {
    let id: UUID
    let data: Data
    let date: Date
    let startedAt: TimeInterval
}

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published private(set) var ready = false
    @Published private(set) var capturing = false
    @Published private(set) var permissionDenied = false
    @Published var error: String?
    var onPhoto: ((CapturedPhoto) -> Void)?
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "local.snapbridge.camera", qos: .userInitiated)
    private var configured = false
    private var wantsRunning = false
    private var notificationTokens: [NSObjectProtocol] = []
    private let processingQueue = DispatchQueue(label: "local.snapbridge.photo-processing", qos: .userInitiated)
    private let captureLock = NSLock()
    private var captureInfo: (UUID, Date, TimeInterval)?
    private var rotationDevice: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?

    override init() {
        super.init()
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] notification in
                guard let self else { return }
                self.ready = false
                self.capturing = false
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
                if error?.code == .mediaServicesWereReset { self.start() }
                else { self.error = error?.localizedDescription ?? "The camera stopped. Reopen ShotSkiff to retry." }
            })
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
                self?.ready = false
            })
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
                self?.ready = true
            })
    }

    deinit { notificationTokens.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        queue.async { self.wantsRunning = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                if allowed { self?.configureAndStart() }
                else { DispatchQueue.main.async { self?.permissionDenied = true } }
            }
        default: permissionDenied = true
        }
    }

    func stop() {
        ready = false
        queue.async {
            self.wantsRunning = false
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configureAndStart() {
        queue.async {
            guard self.wantsRunning else { return }
            do {
                if !self.configured {
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    self.session.sessionPreset = .photo
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    else { throw CameraError.unavailable }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.output)
                    else { throw CameraError.unavailable }
                    self.session.addInput(input)
                    self.session.addOutput(self.output)
                    self.output.maxPhotoQualityPrioritization = .balanced
                    if self.output.isZeroShutterLagSupported { self.output.isZeroShutterLagEnabled = true }
                    if self.output.isResponsiveCaptureSupported { self.output.isResponsiveCaptureEnabled = true }
                    let prepared = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                    prepared.photoQualityPrioritization = .balanced
                    self.output.setPreparedPhotoSettingsArray([prepared], completionHandler: nil)
                    self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
                let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device
                DispatchQueue.main.async {
                    if self.rotationDevice == nil {
                        self.rotationDevice = device
                        self.configureRotation()
                    }
                    self.ready = true; self.permissionDenied = false; self.error = nil
                }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription; self.ready = false }
            }
        }
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        if previewLayer !== layer {
            previewLayer = layer
            configureRotation()
        }
        applyPreviewRotation()
    }

    private func configureRotation() {
        guard let device = rotationDevice else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                                         options: [.initial, .new]) { [weak self] _, _ in
            self?.applyPreviewRotation()
        }
    }

    private func applyPreviewRotation() {
        guard let connection = previewLayer?.connection,
              let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    func focus(at point: CGPoint) {
        queue.async {
            guard let input = self.session.inputs.first as? AVCaptureDeviceInput else { return }
            let device = input.device
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                }
            } catch { /* Focus is optional; the camera keeps automatic focus. */ }
        }
    }

    func capture() {
        guard ready, !capturing else { return }
        capturing = true
        captureLock.lock()
        captureInfo = (UUID(), Date(), PerformanceTrace.now())
        captureLock.unlock()
        let rotation = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        queue.async {
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .balanced
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
                connection.videoRotationAngle = rotation
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let raw = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.capturing = false
                self.error = error?.localizedDescription ?? "The photo could not be captured. Please try again."
            }
            return
        }
        captureLock.lock()
        let info = captureInfo ?? (UUID(), Date(), PerformanceTrace.now())
        captureLock.unlock()
        PerformanceTrace.record("camera_processing", id: info.0, since: info.2, bytes: raw.count)
        processingQueue.async {
            let start = PerformanceTrace.now()
            do {
                let data = try PhotoProcessing.prepareJPEG(raw)
                PerformanceTrace.record("phone_prepare", id: info.0, since: start, bytes: data.count)
                let captured = CapturedPhoto(id: info.0, data: data, date: info.1, startedAt: info.2)
                DispatchQueue.main.async { self.capturing = false; self.onPhoto?(captured) }
            } catch {
                DispatchQueue.main.async { self.capturing = false; self.error = error.localizedDescription }
            }
        }
    }
}

enum CameraError: LocalizedError {
    case unavailable
    var errorDescription: String? { "The camera is unavailable. Try again on your iPhone." }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self)))
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraController
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.attachPreviewLayer(view.previewLayer)
        view.onFocus = camera.focus
        return view
    }
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        camera.attachPreviewLayer(uiView.previewLayer)
    }
}
