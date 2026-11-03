import AVFoundation
import Combine

final class MirrorSessionRunner: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.nubrix.mirror.session", qos: .userInitiated)

    func start(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            if session.inputs.isEmpty {
                guard let device = Self.pickDevice(),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    completion(false)
                    return
                }
                session.beginConfiguration()
                if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    completion(false)
                    return
                }
                session.addInput(input)
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            session.commitConfiguration()
        }
    }

    private static func pickDevice() -> AVCaptureDevice? {
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return front
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
    }
}

@MainActor
final class MirrorCamera: ObservableObject {
    @Published private(set) var state: MirrorCameraState = .starting

    nonisolated let runner = MirrorSessionRunner()
    private var generation = 0

    var session: AVCaptureSession { runner.session }

    func start() {
        generation += 1
        let current = generation
        state = .starting
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run(current)
        case .notDetermined:
            state = .needsPermission
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    func requestAccess(completion: @escaping @MainActor @Sendable () -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
            start()
            completion()
            return
        }
        let current = generation
        state = .starting
        Task { @MainActor [weak self] in
            let result = await Permissions.client.request(.camera)
            completion()
            guard let self, self.generation == current else { return }
            if result == .granted { self.run(current) } else { self.state = .denied }
        }
    }

    func stop() {
        generation += 1
        runner.stop()
        state = .starting
    }

    private func run(_ current: Int) {
        runner.start { ok in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.state = ok ? .running : .unavailable
            }
        }
    }
}
