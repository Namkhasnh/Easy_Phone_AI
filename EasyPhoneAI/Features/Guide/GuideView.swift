import SwiftUI

/// S23 "Khoai hướng dẫn" (4H.3, UI_SCREENS_P4 S23, D-337): money warnings (D-339) · AI note (D-338) · the current
/// step in large text · "Bước tiếp" (Primary) / "Nói lại" (Secondary) / "Bước trước" (link).
struct GuideView: View {
    @State var viewModel: GuideViewModel
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .background(Tokens.Colors.bg)
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .onDisappear { viewModel.leave() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { viewModel.resume() } }
            .sheet(item: $viewModel.quotaBlock) { QuotaBlockSheet(block: $0) }
            .accessibilityIdentifier("screen.S23")
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .loading:
            VStack(spacing: Tokens.Space.l) {
                ProgressView()
                Text("guide.loading")
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unsupported:
            VStack {
                EmptyState(systemImage: "questionmark.circle", titleKey: "common.unsupported",
                           bodyKey: "guide.unsupported.body")
                Spacer()
                PrimaryButton("common.close") { router.path.removeLast() }
                    .padding(Tokens.Space.screenPadding)
            }
        case .failed(let message):
            VStack {
                EmptyState(systemImage: "exclamationmark.triangle", titleKey: LocalizedStringKey(message.key))
                Spacer()
                PrimaryButton("common.retry") { Task { await viewModel.load() } }
                    .padding(Tokens.Space.screenPadding)
            }
        case .guide(let guide):
            guideBody(guide)
        }
    }

    private func guideBody(_ guide: Guide) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Text(guide.title.isEmpty ? viewModel.question : guide.title)
                    .font(Tokens.Fonts.display)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if viewModel.isMoneyRelated {
                    warnings(guide)
                    callFamily
                }
                if viewModel.isAIWritten {
                    Label("guide.ai.note", systemImage: "info.circle")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                stepCard
                if viewModel.isListening {
                    Label("guide.listening", systemImage: "mic.fill")
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.primary)
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { buttons }
    }

    private func warnings(_ guide: Guide) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Label("guide.warning.title", systemImage: "exclamationmark.shield.fill")
                .font(Tokens.Fonts.title)
                .foregroundStyle(Tokens.Colors.textPrimary)
            ForEach(GuideViewModel.fixedWarningKeys, id: \.self) { key in
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(verbatim: "•")
                    Text(LocalizedStringKey(key))
                }
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
            }
            if !guide.scamWarnings.isEmpty {
                Text("guide.warning.ai")
                    .font(Tokens.Fonts.label)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .padding(.top, Tokens.Space.xs)
                ForEach(guide.scamWarnings, id: \.self) { w in
                    Text(verbatim: "• \(w)")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                }
            }
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colors.warningBg, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .accessibilityElement(children: .combine)
    }

    /// 4H.4 (D-339): under the warnings, before the steps.
    private var callFamily: some View {
        SecondaryButton("guide.callFamily", systemImage: "phone.fill") {
            if let id = viewModel.callFamilyDraft() { router.push(.conversation(id)) }
        }
    }

    @ViewBuilder private var stepCard: some View {
        if let step = viewModel.step {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                Text(viewModel.stepLabel)
                    .font(Tokens.Fonts.label)
                    .foregroundStyle(Tokens.Colors.primary)
                Text(step.text)
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                if let hint = step.hint {
                    Label(hint, systemImage: "lightbulb")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            .padding(Tokens.Space.l)
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.rowMinHeight, alignment: .leading)
            .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .accessibilityElement(children: .combine)
        }
    }

    private var buttons: some View {
        VStack(spacing: Tokens.Space.m) {
            if viewModel.isLast {
                PrimaryButton("common.done") { viewModel.leave(); router.path.removeLast() }
            } else {
                PrimaryButton("guide.next") { viewModel.tapNext() }
            }
            SecondaryButton(viewModel.isReading ? "common.stopReading" : "guide.repeat",
                            systemImage: "speaker.wave.2") { Task { await viewModel.readStep() } }
            if viewModel.index > 0 {
                Button("guide.previous") { viewModel.tapPrevious() }
                    .font(Tokens.Fonts.label)
                    .tint(Tokens.Colors.primary)
                    .frame(minHeight: Tokens.Size.tapTargetMin)
            }
        }
        .padding(Tokens.Space.screenPadding)
        .background(Tokens.Colors.bg)
        .overlay(alignment: .top) { Divider() }
    }
}

#Preview {
    NavigationStack {
        GuideView(viewModel: GuideViewModel(question: "Hướng dẫn chuyển tiền qua app ngân hàng",
                                            api: MockAPIClient()))
    }
    .environment(Router())
}
