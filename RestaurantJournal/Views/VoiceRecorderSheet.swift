import SwiftUI
import SwiftData

struct VoiceRecorderSheet: View {
    let visit: Visit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var capture = VoiceCaptureService()
    @StateObject private var player = AudioPlayerService()

    private enum Stage { case idle, recording, review }
    @State private var stage: Stage = .idle
    @State private var draftTranscript = ""
    @State private var recordedFilename: String?
    @State private var isFinalizing = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch stage {
                case .idle:      idleView
                case .recording: recordingView
                case .review:    reviewView
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.caption)
                }
            }
            .padding()
            .navigationTitle("Voice note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                if stage == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                    }
                }
            }
        }
    }

    // MARK: - Stages

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 80))
                .foregroundStyle(.accent)
            Text("Tap to record").font(.title3)
            Spacer()
            recordButton(title: "Record", color: .accentColor) {
                Task { await startRecording() }
            }
        }
    }

    private var recordingView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 80))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: true)
            Text("Listening…").font(.title3)

            ScrollView {
                Text(capture.currentTranscript.isEmpty ? "Start speaking — your words appear here." : capture.currentTranscript)
                    .font(.body)
                    .foregroundStyle(capture.currentTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .animation(.default, value: capture.currentTranscript)
            }
            .frame(maxHeight: 220)

            Spacer()
            recordButton(title: isFinalizing ? "Finishing…" : "Stop", color: .red) {
                Task { await stop() }
            }
            .disabled(isFinalizing)
        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcript")
                .font(.headline)
            TextEditor(text: $draftTranscript)
                .frame(minHeight: 160)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))

            if let url = recordedURL {
                Button {
                    player.toggle(url)
                } label: {
                    Label(
                        player.isPlaying(url) ? "Stop" : "Listen to recording",
                        systemImage: player.isPlaying(url) ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .font(.body.weight(.medium))
                }
            }

            Button(role: .destructive) {
                discardAndRerecord()
            } label: {
                Label("Re-record", systemImage: "arrow.counterclockwise")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(color)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Actions

    private var recordedURL: URL? {
        recordedFilename.map {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent($0)
        }
    }

    private func startRecording() async {
        errorText = nil
        let ok = await capture.requestPermissions()
        guard ok else {
            errorText = "Microphone and Speech permissions are required."
            return
        }
        do {
            try capture.startRecording()
            stage = .recording
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func stop() async {
        isFinalizing = true
        let result = await capture.stopRecording()
        isFinalizing = false
        if let (filename, transcript) = result {
            recordedFilename = filename
            draftTranscript = transcript
            stage = .review
        } else {
            stage = .idle
        }
    }

    private func discardAndRerecord() {
        player.stop()
        deleteRecordingFile()
        recordedFilename = nil
        draftTranscript = ""
        stage = .idle
    }

    private func save() {
        player.stop()
        guard let filename = recordedFilename else { return }
        let trimmed = draftTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = VoiceNote(
            audioFilename: filename,
            recordedAt: Date(),
            transcript: trimmed.isEmpty ? nil : trimmed
        )
        note.visit = visit
        modelContext.insert(note)
        try? modelContext.save()
        dismiss()
    }

    private func cancel() {
        player.stop()
        if capture.isRecording { capture.cancelRecording() }
        if stage == .review { deleteRecordingFile() } // discard the unsaved take
        dismiss()
    }

    private func deleteRecordingFile() {
        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
