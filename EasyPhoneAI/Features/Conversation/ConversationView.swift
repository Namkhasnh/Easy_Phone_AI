import SwiftUI

/// S03 Conversation (UI_SCREENS S03). Modes: listening, transcript ready, working, follow-up, unsupported, answer (4L.2).
struct ConversationView: View {
    @State var viewModel: ConversationViewModel
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var hintIndex = 0
    @FocusState private var textFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                if let caption = viewModel.replyCaption {
                    Label { Text(verbatim: caption) } icon: { Image(systemName: "arrowshape.turn.up.left") }
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                switch viewModel.mode {
                case .listening: listening
                case .transcript: transcript
                case .working: working
                case .unsupported: unsupported
                case .followUp(let followUp): followUpView(followUp)
                case .answer(let answer): answerView(answer)
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dismissesKeyboard($textFocused)
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
        .onChange(of: viewModel.reviewDraftId) { _, id in
            if let id { router.replaceLast(with: .review(id)) }       // nothing left to ask → S04
        }
        .onChange(of: viewModel.calendarDay) { _, day in
            if let day { router.replaceLast(with: .calendarDay(day)) } // D-294: S11 for that day
        }
        .onChange(of: viewModel.opensReminders) { _, opens in
            if opens { router.replaceLast(with: .reminders) }           // D-313: S12
        }
        .onChange(of: viewModel.guideRequest) { _, request in
            if let request { router.replaceLast(with: .guide(question: request.question, spoken: request.spoken)) }
        }
        .onChange(of: viewModel.opensMail) { _, opens in
            if opens { router.replaceLast(with: .mail(codesOnly: viewModel.mailCodesOnly)) }   // D-304: S21
        }
        .onDisappear { viewModel.onDisappear() }
        .sheet(item: $viewModel.quotaBlock) { block in
            QuotaBlockSheet(block: block)                                 // 1F.7: S16 (free) / S17 (premium)
        }
        .sheet(item: $viewModel.pendingPermission) { pending in
            PermissionSheet(pending: pending,
                            onAllow: { Task { await viewModel.allowPermission() } },
                            onOpenSettings: {
                                viewModel.dismissPermission()
                                // = UIApplication.openSettingsURLString, without importing UIKit (D-014)
                                if let url = URL(string: "app-settings:") { openURL(url) }
                            },
                            onLater: { viewModel.dismissPermission() })
        }
        .accessibilityIdentifier("screen.S03")
    }

    // MARK: - Mode 1: listening

    @ViewBuilder private var listening: some View {
        if viewModel.showsMascot && typeSize < .accessibility3 {
            listeningKhoai                                   // D-327 S03 v2; "Dừng" stays in the bottom bar (AC1)
        } else {
            assistantBubble("conv.listening.title")
            HStack {
                Spacer()
                ListeningMic(isListening: true) { Task { await viewModel.stopListening() } }
                Spacer()
            }
        }
        if !viewModel.listeningText.isEmpty {
            userBubble {
                Text(verbatim: viewModel.listeningText)
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

    /// D-327 S03 v2 (Figma "S03 Đang nghe · Khoai v2"): "Mình đang nghe…" bubble over Khoai in a round window
    /// (owner's clip: only the window's inside, clipped to a circle under a clean honey ring). Reduce Motion → still.
    private var listeningKhoai: some View {
        VStack(spacing: Tokens.Space.s) {
            Text("conv.listening.title")
                .font(Tokens.Fonts.title)
                .foregroundStyle(Tokens.Colors.onHoney)
                .padding(.horizontal, Tokens.Space.l)
                .padding(.vertical, Tokens.Space.s)
                .background(Tokens.Colors.honey, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                .accessibilityAddTraits(.isHeader)
            Group {
                if reduceMotion || MascotVideoClip.url(MascotVideoClip.listeningWindow) == nil {
                    Image(MascotVideoClip.listeningWindowStill).resizable().interpolation(.high).scaledToFit()
                } else {
                    MascotVideoView(files: [MascotVideoClip.listeningWindow], still: MascotVideoClip.listeningWindowStill)
                }
            }
            .clipShape(Circle())                             // the clip is the window's inside; the ring is drawn here
            .overlay { Circle().strokeBorder(Tokens.Colors.honey, lineWidth: 8) }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .frame(width: 220, height: 220)                  // decorative, fixed-size slot (not text)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
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
        assistantBubble(live: true) {
            HStack(spacing: Tokens.Space.s) {
                ProgressView().tint(Tokens.Colors.primary)
                Text("conv.working")
            }
        }
    }

    // MARK: - Mode 4: follow-up (spec §6.2 AC3, D-251)

    @ViewBuilder private func followUpView(_ followUp: ConversationViewModel.FollowUp) -> some View {
        userBubble {
            Text(verbatim: viewModel.text)
                .font(Tokens.Fonts.fieldValue)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        assistantBubble(live: true) { Text(verbatim: followUp.question) }   // the ONE question, already localized
        if !followUp.chips.isEmpty {
            // Each chip ≥ 56pt; tapping fills the field on device — no AI call, no unit (D-251).
            // One chip per row at AX sizes so a date never wraps into one word per line.
            let columns = typeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.adaptive(minimum: 150), spacing: Tokens.Space.s)]
            LazyVGrid(columns: columns, spacing: Tokens.Space.s) {
                ForEach(followUp.chips) { chip in
                    Button { viewModel.pick(chip) } label: {
                        Text(verbatim: chip.label)
                            .font(Tokens.Fonts.button)
                            .foregroundStyle(Tokens.Colors.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Tokens.Space.m)
                            .frame(maxWidth: .infinity, minHeight: Tokens.Size.buttonMinHeight, maxHeight: .infinity)
                            .background(Tokens.Colors.secondaryFill, in: RoundedRectangle(cornerRadius: Tokens.Radius.button))
                            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if let notice = viewModel.noticeKey {
            assistantBubble(LocalizedStringKey(notice))
        }
        HStack {
            Spacer()
            ListeningMic(isListening: false) { Task { await viewModel.listenForAnswer() } }
            Spacer()
        }
        // TODO(spec): S03 mode 4 gives no placeholder for the answer field; the S02 one is reused.
        TextField("home.input.placeholder", text: $viewModel.answerText, axis: .vertical)
            .font(Tokens.Fonts.body)
            .foregroundStyle(Tokens.Colors.textPrimary)
            .lineLimit(1...5)
            .padding(.horizontal, Tokens.Space.l)
            .padding(.vertical, Tokens.Space.m)
            .frame(minHeight: Tokens.Size.buttonMinHeight)
            .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.button))
            .overlay { RoundedRectangle(cornerRadius: Tokens.Radius.button).strokeBorder(Tokens.Colors.border) }
            .focused($textFocused)
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

    // MARK: - Mode 6: answer (4L.2)

    @ViewBuilder private func answerView(_ answer: String) -> some View {
        if !viewModel.text.isEmpty {
            userBubble {
                Text(verbatim: viewModel.text)                         // the question as asked
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        assistantBubble(live: true) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text(verbatim: answer)                              // catalog sentence with values (LunarQuestion)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                TextLinkButton(viewModel.isReading ? "common.stopReading" : "common.readAloud") {
                    Task { await viewModel.readAnswer() }
                }
            }
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
            case .followUp:
                if viewModel.canSendAnswer {                           // primaries: mic + "Gửi" only (D-183)
                    PrimaryButton("conv.send") { textFocused = false; Task { await viewModel.sendAnswer() } }
                }
                SecondaryButton("conv.followup.skip") {
                    if let id = viewModel.skipFollowUp() { router.push(.review(id)) }
                }
            case .answer:
                PrimaryButton("common.done") { router.popToRoot() }
                SecondaryButton("conv.answer.askMore", systemImage: "mic") { Task { await viewModel.askMore() } }
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

    /// `live` (owner 2026-11-22: "phần nhận lệnh chưa có chuyển động"): the bubble Khoai is talking in right now
    /// (working, the follow-up question) gets a bigger moving Khoai (thinking / asking clip); older bubbles keep one
    /// still frame. Hidden at AX3+ like S02 so the text keeps the width.
    private func assistantBubble<Content: View>(live: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: live ? .center : .top, spacing: Tokens.Space.s) {
            if live && viewModel.showsMascot && typeSize < .accessibility3 {
                MascotView(pose: viewModel.mascotPose, size: 96, style: .video)
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            } else if viewModel.showsMascot {
                // Pose follows the mode (UI_SCREENS S03): listening / thinking / asking / sorry.
                // D-327: one still smiling Khoai per bubble (a clip per bubble would be many players at once).
                MascotView(pose: viewModel.mascotPose, size: Tokens.Size.stepBadge + 8, forceStill: true,
                           style: .video)                    // no backdrop (owner)
                    .frame(width: Tokens.Size.stepBadge + 8, height: Tokens.Size.stepBadge + 8)
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
        textFocused = false
        Task { await viewModel.send() }
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
    return ConversationViewModel(draftId: id, repository: repo, speech: speech, api: MockAPIClient(), tts: MockTTSService(),
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

#Preview("Follow-up with chips") {
    NavigationStack {
        ConversationView(viewModel: conversationModePreview {
            $0.showFollowUp(.init(question: "Bạn muốn hẹn thứ Sáu nào?", chips: [
                .init(fieldId: "startDate", value: "2026-11-13T09:00:00+07:00", label: "Thứ Sáu 13/11"),
                .init(fieldId: "startDate", value: "2026-11-20T09:00:00+07:00", label: "Thứ Sáu 20/11"),
            ]))
        })
    }
    .environment(Router())
}

#Preview("Speech unavailable, dark") {
    NavigationStack { ConversationView(viewModel: conversationPreviewModel(speechError: .unavailable("speech.vi.unavailable"))) }
        .environment(Router())
        .preferredColorScheme(.dark)
}
