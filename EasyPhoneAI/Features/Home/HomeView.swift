import SwiftUI

/// S02 Home (UI_SCREENS S02). Primary buttons on this screen: mic and "Gửi" only (D-183).
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.xl) {
                if viewModel.showsMascot && typeSize < .accessibility3 {
                    mascotSlot
                }
                Text("home.greeting")
                    .font(Tokens.Fonts.display)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                // TODO(spec): offline banner needs a network monitor; no service for it yet (ARCHITECTURE §4).
                if let quota = viewModel.quotaLowMessage(appState.entitlement) {
                    Banner(message: quota, style: .warning)
                }
                VStack(spacing: Tokens.Space.s) {
                    ListeningMic(isListening: false) { router.push(.conversation(nil)) }
                    Text("home.mic.caption")
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .accessibilityHidden(true)            // the mic's own label says it
                }
                // TODO(spec): S02 does not place `home.tip.firstRun`; below the mic so it never pushes the mic off screen at AX5.
                if viewModel.showsFirstRunTip {
                    Text("home.tip.firstRun")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                inputRow
                SecondaryButton("home.camera", systemImage: "camera") { router.push(.ocr) }
                quickLinks
                unfinishedSection
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .background(Tokens.Colors.bg)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                toolbarButton("home.toolbar.history", systemImage: "clock.arrow.circlepath") { router.push(.history) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                toolbarButton("home.toolbar.settings", systemImage: "gearshape") { router.push(.settings) }
            }
        }
        .onAppear { viewModel.load() }
        .accessibilityIdentifier("screen.S02")
    }

    // MARK: - Parts

    /// Khoai waves once, then idles (UI_SCREENS S02, P-41). Decorative, fixed-size slot (~96pt), no backdrop.
    private var mascotSlot: some View {
        MascotView(pose: .greeting, size: 104)
            .frame(width: 104, height: 104)
            .accessibilityHidden(true)
    }

    /// Simple mode: icon + text; otherwise icon only, the text stays the VoiceOver label (UI_SCREENS S02).
    private func toolbarButton(_ key: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            let label = Label { Text(key) } icon: { Image(systemName: systemImage) }
            if viewModel.settings.simpleMode {
                label.labelStyle(.titleAndIcon).font(Tokens.Fonts.label)
            } else {
                label.labelStyle(.iconOnly)                     // VoiceOver still reads the title
            }
        }
        .frame(minHeight: Tokens.Size.tapTargetMin)
        .tint(Tokens.Colors.primary)
    }

    /// Multi-line field (≥ 56pt) + trailing "Gửi" when non-empty; stacked at AX sizes so neither is squeezed.
    private var inputRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tokens.Space.s))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: Tokens.Space.s))
        return layout {
            TextField("home.input.placeholder", text: $viewModel.inputText, axis: .vertical)
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .lineLimit(1...5)
                .padding(.horizontal, Tokens.Space.l)
                .padding(.vertical, Tokens.Space.m)
                .frame(minHeight: Tokens.Size.buttonMinHeight)
                .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.button))
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.button).strokeBorder(Tokens.Colors.border)
                }
            if viewModel.canSend {
                Button(action: send) {
                    Text("home.send")
                        .font(Tokens.Fonts.button)
                        .foregroundStyle(Tokens.Colors.onPrimary)
                        .padding(.horizontal, Tokens.Space.l)
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil,
                               minHeight: Tokens.Size.buttonMinHeight)
                        .background(Tokens.Colors.primary, in: RoundedRectangle(cornerRadius: Tokens.Radius.button))
                        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 64pt tiles; 3 per row, 2 per row at AX sizes (UI_SCREENS S02).
    private var quickLinks: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.m),
                            count: typeSize.isAccessibilitySize ? 2 : 3)
        return LazyVGrid(columns: columns, spacing: Tokens.Space.m) {
            ForEach(viewModel.quickLinks) { link in
                Button { router.push(link.route) } label: {
                    VStack(spacing: Tokens.Space.xs) {
                        Image(systemName: link.symbol).accessibilityHidden(true)
                        Text(LocalizedStringKey(link.titleKey))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Tokens.Fonts.label)
                    .foregroundStyle(Tokens.Colors.primary)
                    .padding(Tokens.Space.s)
                    .frame(maxWidth: .infinity, minHeight: Tokens.Size.rowMinHeight, maxHeight: .infinity)   // equal tiles per row
                    .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                    .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Việc chưa xong" (D-244): max 3 rows + "Xem tất cả" → S14.
    private var unfinishedSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("home.unfinished.title")
                .font(Tokens.Fonts.title)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if viewModel.unfinished.isEmpty {
                Text("home.unfinished.empty")
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(viewModel.unfinished) { row in
                    Button { router.push(.review(row.id)) } label: { DraftRowView(row: row) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Tokens.Space.l)
                        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                }
                TextLinkButton("common.seeAll") { router.push(.history) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func send() {
        guard let id = viewModel.send() else { return }
        router.push(.conversation(id))
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu")

@MainActor
private func homePreviewModel(simple: Bool = false, empty: Bool = false) -> HomeViewModel {
    func draft(_ kind: TaskKind, _ op: TaskOperation, _ state: TaskState, _ values: [String: String], ago: TimeInterval) -> TaskDraft {
        let step = TaskStep(order: 0, kind: kind, operation: op, state: state,
                            fields: values.map { Field(id: $0.key, type: .text, value: $0.value) })
        let d = TaskDraft(createdAt: .now.addingTimeInterval(-ago), inputMode: .voice, originalInput: "x", steps: [step])
        d.updatedAt = .now.addingTimeInterval(-ago)
        return d
    }
    let repo = empty ? MockTaskRepository() : MockTaskRepository(drafts: [
        draft(.sms, .open, .awaitingApproval, ["recipientName": "anh Minh"], ago: 600),
        draft(.call, .open, .handedOff, ["recipientName": "mẹ"], ago: 3_600),
        draft(.reminder, .create, .needsInfo, ["title": "Uống thuốc"], ago: 90_000),
        draft(.reminder, .create, .failed, ["title": "Mua sữa"], ago: 200_000),
    ])
    let local = MockLocalDataRepository()
    local.settings().simpleMode = simple
    return HomeViewModel(repository: repo, localData: local)
}

#Preview("Light") {
    NavigationStack {
        HomeView(viewModel: homePreviewModel())
            .toolbar { ToolbarItem(placement: .principal) { DemoDataBadge() } }
    }
    .environment(Router())
    .environment(AppState())
}

#Preview("First run, dark") {
    NavigationStack { HomeView(viewModel: homePreviewModel(empty: true)) }
        .environment(Router())
        .environment(AppState())
        .preferredColorScheme(.dark)
}

#Preview("Simple mode, AX5") {
    NavigationStack { HomeView(viewModel: homePreviewModel(simple: true)) }
        .environment(Router())
        .environment(AppState())
        .dynamicTypeSize(.accessibility5)
}
