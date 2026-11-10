import SwiftUI

/// S15 Settings (UI_SCREENS S15). `List(.insetGrouped)`, rows ≥ 56pt, sections in the documented order.
struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = viewModel.settings
        List {
            Group {
            accountSection

            Section(header: header("settings.voice")) {
                Toggle(isOn: $settings.voiceEnabled) { rowText("settings.voice.enabled") }
                    .onChange(of: settings.voiceEnabled) { viewModel.save() }
                    .frame(minHeight: Tokens.Size.buttonMinHeight)
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    rowText("settings.voice.rate")
                    Slider(value: $settings.speechRate, in: 0.3...0.6) {
                        Text("settings.voice.rate")
                    } minimumValueLabel: {
                        Text("settings.voice.rate.slow").font(Tokens.Fonts.label)
                    } maximumValueLabel: {
                        Text("settings.voice.rate.fast").font(Tokens.Fonts.label)
                    } onEditingChanged: { editing in if !editing { viewModel.save() } }
                }
                .padding(.vertical, Tokens.Space.s)
                // TODO(spec): range of the rate slider is not specified; 0.3–0.6 around the 0.45 default (DATA_MODEL §5).
                SecondaryButton("settings.voice.test", systemImage: "speaker.wave.2") {
                    Task { await viewModel.testVoice() }
                }
                .padding(.vertical, Tokens.Space.s)
            }

            Section(header: header("settings.display")) {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    rowText("settings.textSize")
                    Text("settings.textSize.note")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    // TODO(spec): the "live preview" content of the text-size row is not specified.
                }
                .padding(.vertical, Tokens.Space.s)
                toggleRow("settings.simpleMode", note: "settings.simpleMode.note", isOn: $settings.simpleMode)
                toggleRow("settings.pet", note: "settings.pet.note", isOn: $settings.petEnabled)
            }

            Section(header: header("settings.memory")) {
                rowText("settings.nicknames")
                if viewModel.nicknames.isEmpty {
                    Text("settings.nicknames.empty")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                } else {
                    ForEach(viewModel.nicknames) { nickname in
                        // TODO(spec): "mẹ → Nguyễn Thị Lan" needs the contact name from ContactsService (1C.7).
                        Text(verbatim: nickname.nickname)
                            .font(Tokens.Fonts.fieldValue)
                            .frame(minHeight: Tokens.Size.buttonMinHeight)
                            .swipeActions { Button("confirm.delete", role: .destructive) { viewModel.deleteNickname(nickname) } }
                    }
                }
                // TODO(spec): "Địa điểm đã lưu" opens S13 (1C.13).
            }

            if viewModel.showsAdvanced {                       // ★ section, hidden in simple mode (P-40)
                Section(header: header("settings.advanced")) {
                    Picker(selection: $settings.snoozeMorningHour) {
                        ForEach(SettingsViewModel.snoozeHours, id: \.self) { hour in
                            Text(verbatim: UserMessage(key: "settings.snoozeHour.value", args: ["\(hour)"]).text).tag(hour)
                        }
                    } label: { rowText("settings.snoozeHour") }
                    .onChange(of: settings.snoozeMorningHour) { viewModel.save() }
                    .frame(minHeight: Tokens.Size.buttonMinHeight)
                    Picker(selection: $settings.preferredMapsApp) {
                        ForEach(SettingsViewModel.mapsApps, id: \.self) { app in
                            Text(verbatim: FieldFormatter.option(fieldId: "mapsApp", value: app) ?? app).tag(app)
                        }
                    } label: { rowText("settings.mapsApp") }
                    .onChange(of: settings.preferredMapsApp) { viewModel.save() }
                    .frame(minHeight: Tokens.Size.buttonMinHeight)
                    // TODO(spec): "Quyền truy cập" rows need PermissionManager (1C.1).
                }
            }

            Section(header: header("settings.connections")) {
                rowText("settings.gmail.soon")
                    .foregroundStyle(Tokens.Colors.textSecondary)   // disabled until Phase 2 (D-150)
                    .accessibilityAddTraits(.isStaticText)
            }

            Section(header: header("settings.data")) {
                actionRow("settings.clearHistory", danger: true) { viewModel.pendingConfirm = .clearHistory }
                actionRow("settings.clearMemory", danger: true) { viewModel.pendingConfirm = .clearMemory }
            }

            Section(header: header("settings.about")) {
                Text("settings.aiDisclosure")                        // D-187
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .padding(.vertical, Tokens.Space.s)
                // TODO(spec): "Chính sách quyền riêng tư" / "Điều khoản sử dụng" open in-app text (1G.6, D-284).
                TextLinkButton("settings.privacy") {}
                TextLinkButton("settings.terms") {}
                Text(verbatim: viewModel.versionText)
                    .font(Tokens.Fonts.caption)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }

            Section {
                actionRow("settings.signOut", danger: false) { viewModel.pendingConfirm = .signOut }
                // TODO(spec): "Xóa tài khoản" needs `DELETE /v1/me` + local wipe (1G.1–1G.2).
            }
            }
            .listRowBackground(Tokens.Colors.surface)          // cards = `surface` (UI_SCREENS §1.1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Tokens.Colors.bg)
        .tint(Tokens.Colors.primary)
        .navigationTitle(Text("settings.title"))
        .sheet(item: $viewModel.pendingConfirm) { confirm in
            ConfirmSheet(titleKey: LocalizedStringKey(confirm.titleKey), bodyKey: LocalizedStringKey(confirm.bodyKey),
                         confirmKey: LocalizedStringKey(confirm.confirmKey),
                         onConfirm: { Task { await viewModel.perform(confirm) } },
                         onCancel: { viewModel.pendingConfirm = nil })
        }
        .onDisappear { viewModel.stopVoice() }
        .accessibilityIdentifier("screen.S15")
    }

    @ViewBuilder private var accountSection: some View {
        Section(header: header("settings.account")) {
            if let plan = appState.entitlement?.plan {
                rowText(plan == .premium ? "settings.plan.premium" : "settings.plan.free")
            }
            // TODO(spec): quota row + reset time + "Nâng cấp Premium" / "Quản lý gói" come with 1F.6–1F.8.
        }
    }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Tokens.Fonts.label)
            .foregroundStyle(Tokens.Colors.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func rowText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Tokens.Fonts.fieldValue)
            .foregroundStyle(Tokens.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: Tokens.Size.buttonMinHeight, alignment: .leading)
    }

    private func toggleRow(_ key: LocalizedStringKey, note: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Toggle(isOn: isOn) { rowText(key) }
                .onChange(of: isOn.wrappedValue) { viewModel.save() }
            Text(note)
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
        .padding(.vertical, Tokens.Space.xs)
    }

    private func actionRow(_ key: LocalizedStringKey, danger: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(Tokens.Fonts.fieldValue)
                .foregroundStyle(danger ? Tokens.Colors.danger : Tokens.Colors.primary)
                .frame(maxWidth: .infinity, minHeight: Tokens.Size.buttonMinHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Light") {
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel(localData: MockLocalDataRepository(), drafts: MockTaskRepository(),
                                                  auth: MockAuthService()))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoDataBadge() } }
    }
    .environment(AppState())
}

#Preview("Dark, AX5") {
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel(localData: MockLocalDataRepository(), drafts: MockTaskRepository(),
                                                  auth: MockAuthService()))
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility5)
}
