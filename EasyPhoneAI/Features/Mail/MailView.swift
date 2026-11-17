import SwiftUI

/// S21 Mail summary (UI_SCREENS S21): account caption, overview card (`honey`) with "Đọc to", one row per message
/// (sender bold, subject, summary, time, "Cần trả lời" tag = icon + text), "Và {count} thư khác", unread note.
struct MailView: View {
    @State var viewModel: MailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                content
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Colors.bg)
        .navigationTitle(Text("mail.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await viewModel.load() } } label: {
                    Label("mail.refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.phase == .loading)
            }
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.stopReading() }
        .accessibilityIdentifier("screen.S21")
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 200)
        case .notConnected:
            connectState(titleKey: "error.gmail_not_connected", buttonKey: "settings.gmail.connect")
        case .needsReconnect:
            connectState(titleKey: "error.gmail_reconnect_required", buttonKey: "settings.gmail.reconnect")
        case .failed(let message):
            Text(verbatim: message.text)
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
            SecondaryButton("common.retry", systemImage: "arrow.clockwise") { Task { await viewModel.load() } }
        case .loaded(let summary):
            loaded(summary)
        }
    }

    private func connectState(titleKey: LocalizedStringKey, buttonKey: LocalizedStringKey) -> some View {
        VStack(spacing: Tokens.Space.l) {
            EmptyState(systemImage: "envelope", titleKey: titleKey, bodyKey: "settings.gmail.note")
            PrimaryButton(buttonKey) { Task { await viewModel.connect() } }
        }
    }

    @ViewBuilder private func loaded(_ summary: GmailSummaryResponse) -> some View {
        Text(verbatim: UserMessage(key: "mail.account", args: [summary.accountEmail]).text)
            .font(Tokens.Fonts.caption)
            .foregroundStyle(Tokens.Colors.textSecondary)
        if summary.messages.isEmpty {
            EmptyState(systemImage: "tray", titleKey: "mail.empty")
        } else {
            overviewCard(summary.overview)
            ForEach(summary.messages) { message in
                row(message)
            }
            if let more = MailViewModel.moreCount(summary) {
                Text(verbatim: UserMessage(key: "mail.more", args: ["\(more)"]).text)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
        Text("mail.unreadNote")
            .font(Tokens.Fonts.caption)
            .foregroundStyle(Tokens.Colors.textSecondary)
    }

    private func overviewCard(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(verbatim: overview)
                .font(Tokens.Fonts.fieldValue)
                .foregroundStyle(Tokens.Colors.onHoney)
                .fixedSize(horizontal: false, vertical: true)
            readButton(MailViewModel.overviewId, text: overview, tint: Tokens.Colors.onHoney)
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colors.honey, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ message: GmailMessageSummary) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: message.fromName)
                    .font(Tokens.Fonts.fieldValue.bold())
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Spacer(minLength: Tokens.Space.s)
                Text(message.receivedAt, format: .dateTime.hour().minute().day().month())
                    .font(Tokens.Fonts.caption)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            if !message.subject.isEmpty {
                Text(verbatim: message.subject)
                    .font(Tokens.Fonts.label)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            if !message.summary.isEmpty {
                Text(verbatim: message.summary)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textPrimary)
            }
            if message.needsReply {
                Label {                                                                  // icon + text, not color only
                    Text("mail.needsReply").foregroundStyle(Tokens.Colors.textPrimary)
                } icon: {
                    Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(Tokens.Colors.warning)
                }
                .font(Tokens.Fonts.label)
            }
            // TODO(spec): "Trả lời" (UI_SCREENS S21 → S03 with the reply context) comes with the `emailReply` kind (2.6).
            readButton(message.messageId, text: MailViewModel.spoken(message), tint: Tokens.Colors.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, minHeight: Tokens.Size.rowMinHeight, alignment: .leading)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func readButton(_ id: String, text: String, tint: Color) -> some View {
        let reading = viewModel.readingId == id
        return Button { Task { await viewModel.toggleReading(id, text: text) } } label: {
            Label(reading ? "common.stopReading" : "common.readAloud",
                  systemImage: reading ? "stop.fill" : "speaker.wave.2.fill")
                .font(Tokens.Fonts.label)
                .foregroundStyle(tint)
                .frame(minHeight: Tokens.Size.tapTargetMin)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

#Preview("Loaded") {
    NavigationStack {
        MailView(viewModel: MailViewModel(gmail: MockGmailService(accounts: [MockGmailService.sample]),
                                          api: MockAPIClient()))
            .toolbar { ToolbarItem(placement: .topBarLeading) { DemoDataBadge() } }
    }
}

#Preview("Not connected, AX5") {
    NavigationStack {
        MailView(viewModel: MailViewModel(gmail: MockGmailService(), api: MockAPIClient()))
    }
    .dynamicTypeSize(.accessibility5)
}
