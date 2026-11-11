import SwiftUI

/// S11 Calendar today (UI_SCREENS S11). Header "Lịch hôm nay" + date · rows 72pt (time, title, location,
/// "Trùng giờ" with icon + text) · bottom PrimaryButton "Thêm lịch hẹn" → S03 typing mode.
struct CalendarTodayView: View {
    @State var viewModel: CalendarTodayViewModel
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("calendar.title")
                        .font(Tokens.Fonts.display)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: viewModel.dayText)
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                if viewModel.isEmpty {
                    EmptyState(systemImage: "calendar", titleKey: "calendar.empty")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Tokens.Space.xl)
                }
                ForEach(viewModel.rows) { row in
                    Button { viewModel.select(row.id) } label: { EventRow(row: row) }
                        .buttonStyle(.plain)
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Colors.bg)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("calendar.add") { viewModel.addEvent() }
                .padding(Tokens.Space.screenPadding)
                .background(Tokens.Colors.bg)
                .overlay(alignment: .top) { Divider() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await viewModel.load() } }               // also after S04 (edit / delete) pops back
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.load() } }      // back from iOS Settings / Calendar
        }
        .onChange(of: viewModel.newDraftId) { _, id in
            guard let id else { return }
            viewModel.didOpenNewDraft()
            router.push(.conversation(id))
        }
        .onChange(of: viewModel.reviewDraftId) { _, id in
            guard let id else { return }
            viewModel.didOpenReview()
            router.push(.review(id))
        }
        .sheet(item: $viewModel.selected) { _ in detailSheet }
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
        .accessibilityIdentifier("screen.S11")
    }
}

extension CalendarTodayView {
    /// Detail sheet: read-only fields + Primary "Sửa" + Secondary "Xóa" (danger text) + link "Mở trong Lịch".
    fileprivate var detailSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                ForEach(viewModel.detailRows, id: \.labelKey) { row in
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text(LocalizedStringKey(row.labelKey))
                            .font(Tokens.Fonts.label)
                            .foregroundStyle(Tokens.Colors.textSecondary)
                        Text(verbatim: row.value)
                            .font(Tokens.Fonts.fieldValue)
                            .foregroundStyle(Tokens.Colors.textPrimary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
                if !viewModel.canChangeSelected {
                    Text("calendar.recurringUnsupported")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                }
                if let url = viewModel.openInCalendarURL {
                    TextLinkButton("result.openInCalendar") { openURL(url) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Space.screenPadding)
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.canChangeSelected {
                VStack(spacing: Tokens.Space.m) {
                    PrimaryButton("common.edit") { viewModel.change(.update) }
                    SecondaryButton("calendar.delete", role: .destructive) { viewModel.change(.delete) }
                }
                .padding(Tokens.Space.screenPadding)
                .background(Tokens.Colors.bg)
            }
        }
        .background(Tokens.Colors.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// One S11 row, ≥ 72pt: time column (`label`), title (`fieldValue`), location (`body`), conflict = icon + text.
private struct EventRow: View {
    let row: CalendarTodayViewModel.Row

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Text(verbatim: row.time)
                .font(Tokens.Fonts.label)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(verbatim: row.title)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                if let location = row.location {
                    Text(verbatim: location)
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                if row.conflicts {
                    Label("calendar.conflict", systemImage: "exclamationmark.triangle")
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.warning)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Tokens.Space.l)
        .frame(minHeight: 72)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

@MainActor
private func calendarPreviewModel(_ events: [EventSummary], access: PermissionStatus = .granted) -> CalendarTodayViewModel {
    let repo = MockTaskRepository()
    return CalendarTodayViewModel(calendar: MockCalendarService(events), permissions: MockPermissionManager([.calendar: access]),
                                  repository: repo, engine: TaskEngine(repository: repo))
}

@MainActor
private let previewEvents: [EventSummary] = {
    let start = Calendar.current.startOfDay(for: .now)
    func at(_ h: Double) -> Date { start + h * 3600 }
    return [
        EventSummary(id: "1", title: "Sinh nhật mẹ", start: start, end: start + 86_400, isAllDay: true, isRecurring: false),
        EventSummary(id: "2", title: "Khám răng", start: at(9), end: at(10), isAllDay: false,
                     location: "Nha khoa Hoa Sen", isRecurring: false),
        EventSummary(id: "3", title: "Họp tổ dân phố", start: at(9.5), end: at(11), isAllDay: false, isRecurring: false),
        EventSummary(id: "4", title: "Đón cháu", start: at(16.5), end: at(17), isAllDay: false, isRecurring: false),
    ]
}()

private struct CalendarPreview: View {
    let viewModel: CalendarTodayViewModel
    var body: some View {
        NavigationStack {
            CalendarTodayView(viewModel: viewModel)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoDataBadge() } }
        }
        .environment(Router())
    }
}

#Preview("Events + conflict, light") { CalendarPreview(viewModel: calendarPreviewModel(previewEvents)) }
#Preview("Empty, dark") { CalendarPreview(viewModel: calendarPreviewModel([])).preferredColorScheme(.dark) }
#Preview("AX5") { CalendarPreview(viewModel: calendarPreviewModel(previewEvents)).dynamicTypeSize(.accessibility5) }
