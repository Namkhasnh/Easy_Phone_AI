import SwiftUI

/// S14 History (UI_SCREENS S14). Grouped list in fixed order; tap → S04 at `currentStep`; swipe "Ẩn".
struct HistoryView: View {
    @State var viewModel: HistoryViewModel
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if viewModel.isEmpty {
                EmptyState(titleKey: "history.empty")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                Button { router.push(.review(row.id)) } label: { DraftRowView(row: row) }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Tokens.Colors.surface)
                                    .swipeActions(edge: .trailing) {
                                        Button("history.hide") { viewModel.hide(row.id) }
                                            .tint(Tokens.Colors.primary)
                                    }
                                    .accessibilityAction(named: Text("history.hide")) { viewModel.hide(row.id) }
                            }
                        } header: {
                            Text(LocalizedStringKey(section.group.titleKey))
                                .font(Tokens.Fonts.title)
                                .foregroundStyle(Tokens.Colors.textPrimary)
                                .textCase(nil)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Tokens.Colors.bg)
        .navigationTitle(Text("history.title"))
        .onAppear { viewModel.load() }
        .accessibilityIdentifier("screen.S14")
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu")

@MainActor
private func historyPreviewModel() -> HistoryViewModel {
    func draft(_ kind: TaskKind, _ op: TaskOperation, _ states: [TaskState], _ values: [String: String], ago: TimeInterval) -> TaskDraft {
        let steps = states.enumerated().map { i, state in
            TaskStep(order: i, kind: i == 0 ? kind : .reminder, operation: i == 0 ? op : .create, state: state,
                     fields: values.map { Field(id: $0.key, type: .text, value: $0.value) })
        }
        let d = TaskDraft(createdAt: .now.addingTimeInterval(-ago), inputMode: .voice, originalInput: "x", steps: steps)
        d.updatedAt = .now.addingTimeInterval(-ago)
        return d
    }
    let repo = MockTaskRepository(drafts: [
        draft(.sms, .open, [.awaitingApproval], ["recipientName": "anh Minh"], ago: 600),
        draft(.calendarEvent, .create, [.succeeded, .awaitingApproval], ["title": "Khám răng"], ago: 3_600),
        draft(.call, .open, [.handedOff], ["recipientName": "mẹ"], ago: 90_000),
        draft(.reminder, .create, [.succeeded], ["title": "Uống thuốc"], ago: 200_000),
        draft(.reminder, .create, [.cancelled], ["title": "Mua sữa"], ago: 300_000),
    ])
    return HistoryViewModel(repository: repo)
}

#Preview("Light") {
    NavigationStack {
        HistoryView(viewModel: historyPreviewModel())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoDataBadge() } }
    }
    .environment(Router())
}

#Preview("Empty, dark") {
    NavigationStack { HistoryView(viewModel: HistoryViewModel(repository: MockTaskRepository())) }
        .environment(Router())
        .preferredColorScheme(.dark)
}
