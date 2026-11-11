import SwiftUI

/// S04 Review (UI_SCREENS S04). Focus order: title → badge → banner → fields → buttons.
struct ReviewView: View {
    @State var viewModel: ReviewViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ScrollView {
            if let step = viewModel.step {
                content(step)
            }
        }
        .background(Tokens.Colors.bg)
        .safeAreaInset(edge: .bottom) {
            if viewModel.showsActionBar {
                actionBar
            } else if let card = viewModel.resultCard {
                resultCard(card)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { titleFocused = true }
        .task {
            await viewModel.loadContactName()
            viewModel.openPendingPicker()
        }
        .sheet(isPresented: Binding(get: { viewModel.picking != nil },
                                    set: { if !$0 { viewModel.pickingFieldId = nil } })) {
            if let picking = viewModel.picking {
                PickerSheet(ambiguity: picking.ambiguity) { candidate in
                    let fieldId = picking.field.id                       // captured before the sheet closes
                    Task { await viewModel.pick(candidate, fieldId: fieldId) }
                }
            }
        }
        .onChange(of: viewModel.step?.state) { titleFocused = true }      // focus the title after each result (§9)
        .onChange(of: viewModel.didClose) { _, closed in if closed { dismiss() } }
        .onChange(of: viewModel.didFinish) { _, finished in if finished { router.popToRoot() } }
        .sensoryFeedback(trigger: viewModel.step?.state) { _, new in      // §1.3 haptics
            switch new {
            case .succeeded: .success
            case .failed: .warning
            default: nil
            }
        }
        .sheet(isPresented: Binding(get: { viewModel.editingFieldId != nil },
                                    set: { if !$0 { viewModel.editingFieldId = nil } })) {
            if let editor = viewModel.editor { FieldEditorView(viewModel: editor) }
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
        .accessibilityIdentifier("screen.S04")
    }

    private func content(_ step: TaskStep) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            if let key = viewModel.titleKey {
                Text(LocalizedStringKey(key))
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            }
            if let position = viewModel.stepPosition {
                StepIndicator(current: position.current, total: position.total)
            }
            StateBadge(step: step)
            // TODO(spec): calendar conflict card (`review.conflict.*`) needs CalendarService (1C.2).
            if let banner = viewModel.banner {
                Banner(message: banner, style: .warning)
            }
            ForEach(viewModel.visibleFields) { field in
                FieldRow(field: field, kind: step.kind, displayValue: viewModel.displayValue(field),
                         onEdit: { Task { await viewModel.tapRow(field) } },
                         onChoose: { Task { await viewModel.choose(field) } })
                // TODO(spec): "Xem ảnh gốc" (S10, 1D.8) opens its screen later.
            }
            if let original = viewModel.originalInput {
                Text(verbatim: original)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Tokens.Space.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Xác nhận (or destructive "Xác nhận xóa") · Sửa · Hủy (D-182, D-108).
    private var actionBar: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            PrimaryButton(viewModel.isDelete ? "review.delete.confirm" : "common.confirm",
                          role: viewModel.isDelete ? .destructive : nil,
                          disabledReasonKey: viewModel.disabledReasonKey.map { LocalizedStringKey($0) }) {
                Task { await viewModel.confirm() }
            }
            .disabled(viewModel.blocker != nil)
            if viewModel.isDelete {
                Text("review.delete.hint")
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SecondaryButton("common.edit") { viewModel.startEdit() }
            SecondaryButton("common.cancel") { viewModel.cancel() }
        }
        .padding(Tokens.Space.screenPadding)
        .background(Tokens.Colors.bg)
        .overlay(alignment: .top) { Divider() }              // separates scrolled fields from the pinned bar
    }
}

extension ReviewView {
    /// Result card: replaces the button bar of the finished step (UI_SCREENS S04, D-250). Never a new screen.
    fileprivate func resultCard(_ card: ReviewViewModel.ResultCard) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            HStack(alignment: .top, spacing: Tokens.Space.m) {
                if card.state == .processing {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: card.state.symbolName)
                        .font(.system(size: Tokens.Size.iconHero * 0.6))
                        .foregroundStyle(Self.tint(card.state))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(verbatim: card.message)
                        .font(Tokens.Fonts.title)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    if let detail = card.detail {
                        Text(verbatim: detail)
                            .font(Tokens.Fonts.body)
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            // Titles are already localized (with args); a lookup of the text itself falls back to the text.
            if let primary = card.primary {
                PrimaryButton(LocalizedStringKey(primary.title)) { viewModel.perform(primary.action) }
            }
            if let secondary = card.secondary {
                SecondaryButton(LocalizedStringKey(secondary.title)) { viewModel.perform(secondary.action) }
            }
        }
        .padding(Tokens.Space.screenPadding)
        .background(Tokens.Colors.bg)
        .overlay(alignment: .top) { Divider() }
    }

    private static func tint(_ state: TaskState) -> Color {
        switch state {
        case .succeeded, .userMarkedDone: Tokens.Colors.success
        case .failed: Tokens.Colors.danger
        default: Tokens.Colors.textSecondary
        }
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

@MainActor
private enum ReviewPreviewData {
    static func viewModel(_ make: (FieldCatalog) -> TaskDraft) -> ReviewViewModel {
        let draft = make(.mvp)
        let repo = MockTaskRepository(drafts: [draft])
        let engine = TaskEngine(repository: repo)
        for step in draft.steps { engine.revalidate(stepId: step.id, in: draft) }
        return ReviewViewModel(draftId: draft.id, repository: repo, engine: engine,
                               permissions: MockPermissionManager())
    }

    static func reminder(_ catalog: FieldCatalog) -> TaskDraft {
        let values = ["title": "Uống thuốc", "dueDate": "2099-11-09T08:00:00+07:00"]
        let fields = catalog.fields(.reminder, .create).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, confidence: $0.id == "dueDate" ? 0.5 : 0.95)
        }
        return TaskDraft(inputMode: .voice, originalInput: "Nhắc tôi 8 giờ sáng mai uống thuốc",
                         timeZoneId: "Asia/Ho_Chi_Minh",
                         steps: [TaskStep(order: 0, kind: .reminder, operation: .create, fields: fields)])
    }

    static func smsAmbiguous(_ catalog: FieldCatalog) -> TaskDraft {
        let values = ["recipientName": "anh Minh", "body": "Chiều nay em đến muộn nhé.", "channel": "sms"]
        let fields = catalog.fields(.sms, .open).map { spec in
            Field(id: spec.id, type: spec.type, value: values[spec.id], source: .ai, confidence: 0.9,
                  ambiguity: spec.id == "recipientName"
                    ? Ambiguity(kind: .contact, question: "Bạn muốn nhắn Minh nào?", candidates: []) : nil,
                  deviceOnly: spec.deviceOnly)
        }
        return TaskDraft(inputMode: .voice, originalInput: "Nhắn anh Minh là chiều nay em đến muộn",
                         steps: [TaskStep(order: 0, kind: .sms, operation: .open, fields: fields)])
    }

    static func delete(_ catalog: FieldCatalog) -> TaskDraft {
        let fields = catalog.fields(.calendarEvent, .delete).map {
            Field(id: $0.id, type: $0.type, value: ["title": "Khám răng", "startDate": "2099-11-13T14:00:00+07:00"][$0.id])
        }
        return TaskDraft(inputMode: .text, originalInput: "Xóa lịch khám răng thứ Sáu",
                         timeZoneId: "Asia/Ho_Chi_Minh",
                         steps: [TaskStep(order: 0, kind: .calendarEvent, operation: .delete, fields: fields,
                                          targetRef: "preview-event")])
    }
}

private struct ReviewPreview: View {
    let viewModel: ReviewViewModel
    var body: some View {
        NavigationStack {
            ReviewView(viewModel: viewModel)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoDataBadge() } }
        }
        .environment(Router())
    }
}

#Preview("Reminder, light") {
    ReviewPreview(viewModel: ReviewPreviewData.viewModel(ReviewPreviewData.reminder))
}

#Preview("SMS ambiguous, dark") {
    ReviewPreview(viewModel: ReviewPreviewData.viewModel(ReviewPreviewData.smsAmbiguous))
        .preferredColorScheme(.dark)
}

#Preview("Delete, AX5") {
    ReviewPreview(viewModel: ReviewPreviewData.viewModel(ReviewPreviewData.delete))
        .dynamicTypeSize(.accessibility5)
}
