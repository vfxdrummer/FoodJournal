import SwiftUI
import SwiftData

struct AskJournalView: View {
    @Query(
        filter: #Predicate<Visit> { $0.deletedAt == nil },
        sort: \Visit.date,
        order: .reverse
    )
    private var visits: [Visit]

    @AppStorage(LLMProvider.defaultsKey) private var providerRaw = LLMProvider.claude.rawValue
    @AppStorage("askAutoSpeak") private var autoSpeak = true

    @StateObject private var dictation = SpeechDictationService()
    @StateObject private var speaker = AnswerSpeaker()

    @State private var question = ""
    @State private var answer = ""
    @State private var referencedVisits: [Visit] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showingSettings = false
    @FocusState private var questionFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var provider: LLMProvider { LLMProvider(rawValue: providerRaw) ?? .claude }

    var body: some View {
        NavigationStack {
            answerArea
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider()
                        voiceBar
                    }
                    .background(.bar)
                }
                .navigationTitle("Ask")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        autoSpeak.toggle()
                        if !autoSpeak { speaker.stop() }
                    } label: {
                        Image(systemName: autoSpeak ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    Picker("Model", selection: $providerRaw) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { questionFocused = false }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Answer area

    @ViewBuilder
    private var answerArea: some View {
        if isPristine {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !question.isEmpty {
                        Text(question)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let errorText {
                        Text(errorText).font(.caption).foregroundStyle(.red)
                    }

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(.secondary)
                        }
                    }

                    if !answer.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Text(answer)
                            Spacer(minLength: 0)
                            Button {
                                if speaker.isSpeaking { speaker.stop() } else { speaker.speak(answer) }
                            } label: {
                                Image(systemName: speaker.isSpeaking ? "stop.circle.fill" : "play.circle")
                                    .font(.title3)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if !referencedVisits.isEmpty {
                        Text("Referenced visits").font(.headline)
                        ForEach(referencedVisits) { visit in
                            referencedRow(visit)
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// True when nothing has been asked yet — show the centered invitation instead of the scroll.
    private var isPristine: Bool {
        answer.isEmpty && question.isEmpty && !isLoading
            && !dictation.isListening && errorText == nil
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Ask about your visits")
                .font(.title3.weight(.semibold))
            Text("Tap the mic or type a question — I'll search your journal for the answer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("“Where did we get those tacos after the game?”")
                .font(.callout)
                .italic()
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
            Text("Fair-use limit: up to \(QueryRateLimiter.perMinute)/min and \(QueryRateLimiter.perHour)/hour.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private func referencedRow(_ visit: Visit) -> some View {
        NavigationLink(destination: VisitDetailView(visit: visit)) {
            HStack {
                if let photo = visit.coverPhoto {
                    PhotoThumbnailView(
                        localIdentifier: photo.localIdentifier,
                        targetSize: CGSize(width: 120, height: 120)
                    )
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading) {
                    RestaurantNameLabel(
                        restaurant: visit.restaurant,
                        placeholder: "Unknown",
                        font: .subheadline.bold(),
                        logoSize: 18
                    )
                    Text(visit.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Voice bar

    private var voiceBar: some View {
        VStack(spacing: 10) {
            if dictation.isListening {
                Text(dictation.transcript.isEmpty ? "Listening…" : dictation.transcript)
                    .font(.callout)
                    .foregroundStyle(dictation.transcript.isEmpty ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Ask about your visits…", text: $question, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($questionFocused)

                    if isLoading {
                        ProgressView()
                            .padding(.trailing, 2)
                            .padding(.bottom, 2)
                    } else if canSend {
                        Button {
                            Task { await ask() }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

                Button(action: toggleMic) {
                    Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(dictation.isListening ? Color.red : Color.accentColor)
                        .clipShape(Circle())
                        .symbolEffect(.pulse, isActive: dictation.isListening)
                }
            }
            .animation(.snappy, value: canSend)
            .animation(.snappy, value: isLoading)
        }
        .padding()
    }

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func toggleMic() {
        if dictation.isListening {
            dictation.stop()
            let spoken = dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty {
                question = spoken
                Task { await ask() }
            }
        } else {
            speaker.stop()
            errorText = nil
            answer = ""
            referencedVisits = []
            question = ""
            Task {
                let granted = await dictation.requestPermission()
                guard granted else {
                    errorText = "Microphone and Speech permission are required to ask by voice."
                    return
                }
                do {
                    try dictation.start()
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func ask() async {
        questionFocused = false
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let client = provider.makeClient() else {
            errorText = "No \(provider.displayName) API key. Tap the gear to add one."
            return
        }
        // Client-side throttle — stop spamming before it ever reaches the server.
        if let limitMessage = QueryRateLimiter.blockMessage() {
            errorText = limitMessage
            return
        }
        question = trimmed
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        QueryRateLimiter.record()
        Analytics.log("ask_used", ["provider": provider.rawValue])
        let service = JournalQueryService(client: client)
        do {
            let result = try await service.ask(question: trimmed, visits: visits)
            answer = result.answer
            referencedVisits = result.referencedVisitIDs.compactMap { id in
                visits.first { $0.persistentModelID == id }
            }
            if autoSpeak { speaker.speak(answer) }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
