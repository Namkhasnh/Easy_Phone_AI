import SwiftUI

/// S22 "Ngày giỗ & lễ" (4L.6, UI_SCREENS_P4 S22): today's lunar date, "Ngày đã lưu", "Ngày lễ âm lịch";
/// bottom "Thêm ngày giỗ" → S03. Rows are read-only (change / delete a giỗ from S11, D-331).
struct LunarDaysView: View {
    @State var viewModel: LunarDaysViewModel
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Text("lunarDays.title")
                    .font(Tokens.Fonts.display)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.todayLine)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                section("lunarDays.saved.title")
                if viewModel.loaded && viewModel.saved.isEmpty {
                    EmptyState(systemImage: "moon.stars", titleKey: "lunarDays.saved.empty")
                        .frame(maxWidth: .infinity)
                }
                ForEach(viewModel.saved) { RowView(row: $0) }
                section("lunarDays.holidays.title")
                ForEach(viewModel.holidays) { RowView(row: $0) }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Colors.bg)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("lunarDays.add") { router.push(.conversation(nil)) }
                .padding(Tokens.Space.screenPadding)
                .background(Tokens.Colors.bg)
                .overlay(alignment: .top) { Divider() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .accessibilityIdentifier("screen.S22")
    }

    private func section(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Tokens.Fonts.title)
            .foregroundStyle(Tokens.Colors.textPrimary)
            .padding(.top, Tokens.Space.s)
            .accessibilityAddTraits(.isHeader)
    }

    private struct RowView: View {
        let row: LunarDaysViewModel.Row

        var body: some View {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(row.title)
                    .font(Tokens.Fonts.fieldValue.weight(.semibold))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text(row.lunarLabel)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.primary)
                Text(row.nextLabel)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            .padding(Tokens.Space.l)
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.rowMinHeight, alignment: .leading)
            .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    // "Dữ liệu mẫu" is not needed: no sample rows, only the computed holidays (D-189).
    NavigationStack {
        LunarDaysView(viewModel: LunarDaysViewModel(repository: MockTaskRepository(), calendar: MockCalendarService(),
                                                    reminders: MockRemindersService(),
                                                    permissions: MockPermissionManager()))
    }
    .environment(Router())
}
