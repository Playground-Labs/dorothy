import AVFoundation

enum RecorderError: LocalizedError {
    case permissionPending, denied
    var errorDescription: String? {
        self == .denied ? "Mic access denied" : "Allow mic, then try again"
    }
}

public final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    static let devicesChanged = Notification.Name("Recorder.devicesChanged")
    static let deviceKey = "micDeviceID"

    private var session: AVCaptureSession?
    private let output = AVCaptureAudioFileOutput()
    private var finished = false
    private var started = Date()
    private var observers: [NSObjectProtocol] = []
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("dorothy-dictation.wav")

    override init() {
        super.init()
        output.maxRecordedDuration = CMTime(seconds: 30, preferredTimescale: 600)
        observers = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { _ in
                NotificationCenter.default.post(name: Recorder.devicesChanged, object: nil)
            }
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    static func inputDevices() -> [(id: String, name: String)] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { ($0.uniqueID, $0.localizedName) }
    }

    var level: Float {
        guard output.isRecording, let db = output.connections.first?.audioChannels.first?.averagePowerLevel else { return 0 }
        return min(1, max(0, (db + 50) / 50))
    }

    func start() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw RecorderError.permissionPending
        default: throw RecorderError.denied
        }
        let saved = UserDefaults.standard.string(forKey: Recorder.deviceKey).flatMap(AVCaptureDevice.init(uniqueID:))
        guard let device = saved ?? AVCaptureDevice.default(for: .audio) else { throw CocoaError(.fileReadNoSuchFile) }
        let s = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard s.canAddInput(input), s.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
        s.addInput(input)
        s.addOutput(output)
        // Set after addOutput, else some devices (built-in mic) record in their native 48 kHz float format.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        s.startRunning()
        finished = false
        try? FileManager.default.removeItem(at: url)
        output.startRecording(to: url, outputFileType: .wav, recordingDelegate: self)
        session = s
        started = Date()
    }

    func stop() -> Data? {
        guard let s = session else { return nil }
        let duration = Date().timeIntervalSince(started)
        output.stopRecording()
        let deadline = Date() + 2  // delegate is delivered on main, so pump the run loop instead of blocking
        while !finished && Date() < deadline { RunLoop.current.run(mode: .default, before: Date() + 0.01) }
        s.stopRunning()
        s.removeOutput(output)
        session = nil
        defer { try? FileManager.default.removeItem(at: url) }
        return duration < 0.3 ? nil : try? Data(contentsOf: url)
    }

    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                           from connections: [AVCaptureConnection], error: Error?) {
        finished = true
    }
}
