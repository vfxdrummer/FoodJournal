import Foundation
import AVFoundation
import Speech

@MainActor
final class VoiceCaptureService: NSObject, ObservableObject {
    @Published var isRecording: Bool = false
    /// Updates live as the user speaks, then settles to the final transcription on stop.
    @Published var currentTranscript: String = ""

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentFilename: String?

    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalizeContinuation: CheckedContinuation<String, Never>?

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
        let speechGranted = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        return micGranted && speechGranted
    }

    // MARK: - Recording

    /// Start recording to a file AND stream the mic through the recognizer for live partial results.
    func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        currentTranscript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let filename = "voice_\(UUID().uuidString).caf"
        let url = documentsURL().appendingPathComponent(filename)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        audioFile = file
        currentFilename = filename

        // Live recognition — partial results stream in as audio arrives.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        if let recognizer = speechRecognizer, recognizer.isAvailable {
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    Task { @MainActor in
                        self.currentTranscript = text
                        if isFinal { self.finish(with: text) }
                    }
                } else if error != nil {
                    Task { @MainActor in self.finish(with: self.currentTranscript) }
                }
            }
        }

        // One tap feeds both the recognizer and the on-disk file.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            try? file.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    /// Stop recording and return (filename relative to Documents, final transcript).
    func stopRecording() async -> (String, String)? {
        guard let filename = currentFilename else { return nil }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil // close the file

        let transcript = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            finalizeContinuation = cont
            recognitionRequest?.endAudio()
            // Safety net: if no final result arrives, settle with the latest partial.
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.finish(with: self.currentTranscript)
            }
        }

        recognitionTask = nil
        recognitionRequest = nil
        currentFilename = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (filename, transcript)
    }

    /// Abandon an in-progress recording and delete its file (used when the sheet is dismissed).
    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioFile = nil
        if let filename = currentFilename {
            try? FileManager.default.removeItem(at: documentsURL().appendingPathComponent(filename))
        }
        currentFilename = nil
        finalizeContinuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Resume the stop() continuation exactly once.
    private func finish(with transcript: String) {
        guard let cont = finalizeContinuation else { return }
        finalizeContinuation = nil
        cont.resume(returning: transcript)
    }

    private func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
