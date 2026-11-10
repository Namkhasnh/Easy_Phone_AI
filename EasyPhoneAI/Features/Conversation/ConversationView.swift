import SwiftUI

/// S03 Conversation (UI_SCREENS S03). Modes: listening, transcript ready, working, unsupported (follow-up: 1B.4c).
struct ConversationView: View {
    @State var viewModel: ConversationViewModel
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var hintIndex = 0
    @FocusState private var textFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                switch viewModel.mode {
                case .listening: listening
                case .transcript: transcript
                case .working: working
                case .unsupported: unsupported
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Colors.bg)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // "Hủy" discards nothing: the draft is saved (UI_SCREENS S03, D-104).
                Button("common.cancel") { leave() }
                    .font(Tokens.Fonts.label)
                    .tint(Tokens.Colors.primary)
            }
        }
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("screen.S03")
    }

    // MARK: - Mode 1: listening

    @ViewBuilder private var listening: some View {
        assistantBubble("conv.listening.title")
        HStack {
            Spacer()
            ListeningMic(isListening: true) { Task { await viewModel.stopListening() } }
            Spacer()
        }
        if !viewModel.text.isEmpty {
            userBubble {
                Text(verbatim: viewModel.text)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityAddTraits(.updatesFrequently)
        }
        Text(LocalizedStringKey(ConversationViewModel.hintKeys[hintIndex]))
            .font(Tokens.Fonts.body)
            .foregroundStyle(Tokens.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .task(id: viewModel.mode) {
                // TODO(spec): S03 says "rotating hint" without an interval; every 4 s.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    hintIndex = (hintIndex + 1) % ConversationViewModel.hintKeys.count
                }
            }
    }

    // MARK: - Mode 2: transcript ready (editable, never auto-sent)

    @ViewBuilder private var transcript: some View {
        userBubble {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                // TODO(spec): S03 gives no placeholder for the empty text area; the S02 one is reused.
                TextField("home.input.placeholder", text: $viewModel.text, axis: .vertical)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .lineLimit(2...10)
                    .focused($textFocused)
                    .accessibilityLabel(Text("conv.transcript.edit.a11y"))
                if !viewModel.text.isEmpty {
                    TextLinkButton(viewModel.isReading ? "common.stopReading" : "common.readAloud") {
                        Task { await viewModel.toggleReading() }
                    }
                }
            }
        }
        if let notice = viewModel.noticeKey {
            assistantBubble(LocalizedStringKey(notice))
                .onAppear { textFocused = viewModel.noticeKey == "conv.speech.unavailable" }   // → keyboard
        }
    }

    // MARK: - Mode 3: working

    @ViewBuilder private var working: some View {
        userBubble {
            Text(verbatim: viewModel.text)
                .font(Tokens.Fonts.fieldValue)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        assistantBubble {
            HStack(spacing: Tokens.Space.s) {
                ProgressView().tint(Tokens.Colors.primary)
                Text("conv.working")
            }
        }
    }

    // MARK: - Mode 5: unsupported (spec §11, D-280)

    @ViewBuilder private var unsupported: some View {
        EmptyState(systemImage: "nosign", titleKey: "common.unsupported")
        if let message = viewModel.unsupportedMessage {
            Text(verbatim: message)                                 // backend sentence = data, never a key
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: Tokens.Space.m) {
            switch viewModel.mode {
            case .listening:
                PrimaryButton("conv.listening.stop") { Task { await viewModel.stopListening() } }   // always visible (AC1)
            case .transcript:
                PrimaryButton("conv.send") { send() }
                    .disabled(!viewModel.canSend)
                SecondaryButton("conv.speakAgain", systemImage: "mic") {
                    textFocused = false
                    Task { await viewModel.speakAgain() }
                }
            case .working:
                SecondaryButton("common.cancel") { viewModel.cancelWorking() }
            case .unsupported:
                PrimaryButton("conv.unsupported.home") { router.popToRoot() }
                switch viewModel.unsupportedAction {
                case .rephrase:
                    SecondaryButton("conv.unsupported.rephrase") { viewModel.rephrase() }
                case .openList(let route):
                    SecondaryButton("conv.unsupported.openList") { router.push(route) }
                }
            }
        }
        .padding(Tokens.Space.screenPadding)
        .background(Tokens.Colors.bg)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Bubbles

    /// Assistant bubble: left, `secondaryFill`, with the Khoai avatar slot (P-41).
    private func assistantBubble(_ key: LocalizedStringKey) -> some View {
        assistantBubble { Text(key) }
    }

    private func assistantBubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            if viewModel.showsMascot {
                // TODO(spec): mascot art — `MascotView` with the mode's pose comes with 1B.16; SF Symbol placeholder.
                Image(systemName: "pawprint.fill")
                    .font(Tokens.Fonts.label)
                    .foregroundStyle(Tokens.Colors.onHoney)
                    .frame(width: Tokens.Size.stepBadge, height: Tokens.Size.stepBadge)
                    .background(Tokens.Colors.honey, in: Circle())
                    .accessibilityHidden(true)
            }
            content()
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Tokens.Space.m)
                .background(Tokens.Colors.secondaryFill, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            Spacer(minLength: Tokens.Space.xl)
        }
    }

    /// User bubble: right, `surface`.
    private func userBubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer(minLength: Tokens.Space.xl)
            content()
                .padding(Tokens.Space.m)
                .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }

    // MARK: - Actions

    private func send() {
        guard viewModel.send() else { return }
        router.popToRoot()
    }

    private func leave() {
        viewModel.onDisappear()
        dismiss()
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu")

@MainActor
private func conversationPreviewModel(draftText: String? = nil, speechError: ServiceError? = nil) -> ConversationViewModel {
    let repo = MockTaskRepository()
    var id: UUID?
    if let draftText {
        let draft = TaskDraft(inputMode: .text, originalInput: draftText)
        repo.save(draft)
        id = draft.id
    }
    let speech = MockSpeechService()
    speech.error = speechError
    if speechError != nil { speech.script = [] }
    return ConversationViewModel(draftId: id, repository: repo, speech: speech, tts: MockTTSService(),
                                 localData: MockLocalDataRepository())
}

#Preview("Transcript, light") {
    NavigationStack {
        ConversationView(viewModel: conversationPreviewModel(draftText: "Nhắc tôi 8 giờ sáng mai uống thuốc"))
            .toolbar { ToolbarItem(placement: .principal) { DemoDataBadge() } }
    }
    .environment(Router())
}

@MainActor
private func conversationModePreview(_ apply: (ConversationViewModel) -> Void) -> ConversationViewModel {
    let vm = conversationPreviewModel(draftText: "Xóa hết lịch tuần này")
    apply(vm)
    return vm
}

#Preview("Working") {
    NavigationStack { ConversationView(viewModel: conversationModePreview { $0.showWorking() }) }
        .environment(Router())
}

#Preview("Unsupported bulkAction, dark") {
    NavigationStack {
        ConversationView(viewModel: conversationModePreview {
            $0.showUnsupported(.init(reason: "bulkAction", message: "Chưa hỗ trợ xóa nhiều lịch cùng lúc."))
        })
    }
    .environment(Router())
    .preferredColorScheme(.dark)
}

#Preview("Parse failed, AX5") {
    NavigationStack { ConversationView(viewModel: conversationModePreview { $0.showParseFailed() }) }
        .environment(Router())
        .dynamicTypeSize(.accessibility5)
}

#Preview("Speech unavailable, dark") {
    NavigationStack { ConversationView(viewModel: conversationPreviewModel(speechError: .unavailable("speech.vi.unavailable"))) }
        .environment(Router())
        .preferredColorScheme(.dark)
}
