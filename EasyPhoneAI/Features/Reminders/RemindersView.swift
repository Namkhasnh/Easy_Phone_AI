import SwiftUI

/// S12 Reminders (UI_SCREENS S12). Sections "Quá hạn" / "Sắp tới"; row ≥ 72pt with a 44pt complete circle (one tap,
/// D-107) + title + due time; toast "Đã đánh dấu xong" with "Hoàn tác" (D-248); bottom "Thêm lời nhắc" → S03.
struct RemindersView: View {
    @State var viewModel: RemindersViewModel
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Text("reminders.title")
                    .font(Tokens.Fonts.display)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if viewModel.isEmpty {
                    EmptyState(systemImage: "checklist", titleKey: "reminders.empty")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Tokens.Space.xl)
                }
                ForEach(viewModel.sections) { section in
                    Text(LocalizedStringKey(section.titleKey))
                        .font(Tokens.Fonts.title)
                        .foregroundStyle(section.kind == .overdue ? Tokens.Colors.danger : Tokens.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.rows) { row in
                        ReminderRow(row: row, overdue: section.kind == .overdue,
                                    completing: viewModel.completing.contains(row.id),
                                    onComplete: { Task { await viewModel.complete(row.id) } },
                                    onSnooze: { viewModel.startSnooze(row.id) },
                                    onEdit: { viewModel.change(row.id, .update) },
                                    onDelete: { viewModel.change(row.id, .delete) })
                    }
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Colors.bg)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("reminders.add") { viewModel.addReminder() }
                .padding(Tokens.Space.screenPadding)
                .background(Tokens.Colors.bg)
                .overlay(alignment: .top) { Divider() }
        }
        .toast($viewModel.toast)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await viewModel.load() } }               // also after S03 / S04 pop back
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.load() } }
        }
        .onChange(of: viewModel.reviewDraftId) { _, id in
            guard let id else { return }
            viewModel.didOpenReview()
            router.push(.review(id))
        }
        .sheet(item: $viewModel.snoozing) { _ in snoozeSheet }
        .onChange(of: viewModel.newDraftId) { _, id in
            guard let id else { return }
            viewModel.didOpenNewDraft()
            router.push(.conversation(id))
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
        .accessibilityIdentifier("screen.S12")
    }
}

extension RemindersView {
    /// "Nhắc lại lúc nào?" — 3 rows ≥ 64pt (UI_SCREENS S12); the choice goes to S04, nothing changes before "Xác nhận".
    fileprivate var snoozeSheet: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("reminders.snooze.title")
                .font(Tokens.Fonts.title)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(RemindersViewModel.snoozeOptions, id: \.self) { option in
                Button { viewModel.snooze(option) } label: {
                    Text(verbatim: viewModel.snoozeLabel(option))
                        .font(Tokens.Fonts.fieldValue)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: Tokens.Size.rowMinHeight, alignment: .leading)
                        .padding(.horizontal, Tokens.Space.l)
                        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colors.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// One S12 row: complete circle (44pt tap target) + title (`fieldValue`) + due time (`body`, `danger` when overdue).
private struct ReminderRow: View {
    let row: RemindersViewModel.Row
    let overdue: Bool
    let completing: Bool
    let onComplete: () -> Void
    let onSnooze: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Button(action: onComplete) {
                Image(systemName: completing ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(width: Tokens.Size.tapTargetMin, height: Tokens.Size.tapTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(completing)
            .accessibilityLabel(Text(verbatim: UserMessage(key: "reminders.complete.a11y", args: [row.title]).text))
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(verbatim: row.title)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                if let due = row.due {
                    Text(verbatim: due)
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(overdue ? Tokens.Colors.danger : Tokens.Colors.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Menu {
                Button("reminders.snooze", systemImage: "clock.arrow.circlepath", action: onSnooze)
                Button("common.edit", systemImage: "pencil", action: onEdit)
                Button("confirm.delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(width: Tokens.Size.tapTargetMin, height: Tokens.Size.tapTargetMin)
                    .contentShape(Rectangle())
            }
            // TODO(spec): the menu button has no VoiceOver key in UI_SCREENS; `reminders.menu.a11y` added (PROGRESS DOC-39).
            .accessibilityLabel(Text(verbatim: UserMessage(key: "reminders.menu.a11y", args: [row.title]).text))
        }
        .padding(Tokens.Space.m)
        .frame(minHeight: 72)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

@MainActor
private func remindersPreviewModel(_ items: [ReminderSummary]) -> RemindersViewModel {
    let repo = MockTaskRepository()
    let reminders = MockRemindersService(items)
    let permissions = MockPermissionManager()
    return RemindersViewModel(reminders: reminders, permissions: permissions, repository: repo,
                              engine: TaskEngine(repository: repo,
                                                 executors: [.reminder: RemindersExecutor(reminders: reminders,
                                                                                          permissions: permissions)]))
}

@MainActor
private let previewReminders: [ReminderSummary] = [
    ReminderSummary(id: "1", title: "Uống thuốc huyết áp", dueDate: .now - 3600, isCompleted: false, isRecurring: false),
    ReminderSummary(id: "2", title: "Gọi cho con gái", dueDate: .now + 2 * 3600, isCompleted: false, isRecurring: false),
    ReminderSummary(id: "3", title: "Mua rau", dueDate: nil, isCompleted: false, isRecurring: false),
]

private struct RemindersPreview: View {
    let viewModel: RemindersViewModel
    var body: some View {
        NavigationStack {
            RemindersView(viewModel: viewModel)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoDataBadge() } }
        }
        .environment(Router())
    }
}

#Preview("Overdue + upcoming, light") { RemindersPreview(viewModel: remindersPreviewModel(previewReminders)) }
#Preview("Empty, dark") { RemindersPreview(viewModel: remindersPreviewModel([])).preferredColorScheme(.dark) }
#Preview("AX5") { RemindersPreview(viewModel: remindersPreviewModel(previewReminders)).dynamicTypeSize(.accessibility5) }
