import SwiftUI

/// S15 Settings (UI_SCREENS S15). `List(.insetGrouped)`, rows ≥ 56pt, sections in the documented order.
struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    @Environment(AppState.self) private var appState
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appEnv) private var env
    @State private var showsPaywall = false

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
                toggleRow("settings.autoSend", note: "settings.autoSend.note", isOn: $settings.autoSend)   // D-296
                toggleRow("settings.handsFree", note: "settings.handsFree.note", isOn: $settings.handsFree) // D-312
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
                        Text(verbatim: viewModel.nicknameRow(nickname))
                            .font(Tokens.Fonts.fieldValue)
                            .frame(minHeight: Tokens.Size.buttonMinHeight)
                            .swipeActions { Button("confirm.delete", role: .destructive) { viewModel.deleteNickname(nickname) } }
                    }
                }
                Button { router.push(.places) } label: {
                    HStack {
                        rowText("settings.savedPlaces")
                        Spacer(minLength: Tokens.Space.s)
                        Image(systemName: "chevron.right")
                            .font(Tokens.Fonts.label)
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if viewModel.showsAdvanced {                       // ★ section, hidden in simple mode (P-40)
                Section(header: header("settings.advanced")) {
                    toggleRow("settings.autoConfirm", note: "settings.autoConfirm.note", isOn: $settings.autoConfirm)  // D-299
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
                }
                permissionsSection
            }

            gmailSection

            Section(header: header("settings.data")) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {          // D-301
                    Toggle(isOn: $settings.savePhotos) { rowText("settings.savePhotos") }
                        .onChange(of: settings.savePhotos) { Task { await viewModel.savePhotosChanged() } }
                    Text("settings.savePhotos.note")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                .padding(.vertical, Tokens.Space.xs)
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
                actionRow("settings.deleteAccount", danger: true) { viewModel.pendingConfirm = .deleteAccount }  // S20
                    .disabled(viewModel.deletingAccount)
                if viewModel.deletingAccount {
                    Label { Text("confirm.deleteAccount.progress") } icon: { ProgressView() }
                }
                if let message = viewModel.accountMessage {
                    Text(verbatim: message.text).font(Tokens.Fonts.body).foregroundStyle(Tokens.Colors.danger)
                }
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
                         // S20: the App Store subscription is not cancelled by deleting the account (API_CONTRACT §6.3).
                         noteKey: confirm == .deleteAccount ? "confirm.deleteAccount.subNote" : nil,
                         confirmKey: LocalizedStringKey(confirm.confirmKey),
                         cancelKey: confirm == .deleteAccount ? "confirm.deleteAccount.no" : "common.cancel",
                         onConfirm: { Task { await viewModel.perform(confirm) } },
                         onCancel: { viewModel.pendingConfirm = nil })
        }
        .onDisappear { viewModel.stopVoice() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            viewModel.refreshPermissions()
            Task { await viewModel.loadContactNames() }
        }
        .task {
            await viewModel.loadContactNames()
            await viewModel.loadGmail()
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(viewModel: PaywallViewModel(purchases: env.purchases, api: env.api, userId: signedInUser,
                                                    onPlan: { appState.apply(me: $0) }))
        }
        .accessibilityIdentifier("screen.S15")
    }

    /// ★ "Quyền truy cập" (UI_SCREENS S15): capability + status (§10.4) + "Mở Cài đặt". Read-only; never prompts.
    private var permissionsSection: some View {
        Section(header: header("settings.permissions")) {
            ForEach(viewModel.permissionStatuses, id: \.capability) { row in
                HStack(spacing: Tokens.Space.m) {
                    Image(systemName: PermissionSheet.symbol(row.capability))
                        .foregroundStyle(Tokens.Colors.primary)
                        .accessibilityHidden(true)
                    // TODO(spec): row label = `perm.<c>.feature` (DOC-37); S15 names no label per capability.
                    rowText(LocalizedStringKey("perm.\(row.capability.rawValue).feature"))
                    Spacer(minLength: Tokens.Space.s)
                    Text(LocalizedStringKey(row.status.labelKey))
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: Tokens.Size.buttonMinHeight)
                .accessibilityElement(children: .combine)
            }
            SecondaryButton("common.openSettings") {
                // = UIApplication.openSettingsURLString, without importing UIKit (D-014)
                if let url = URL(string: "app-settings:") { openURL(url) }
            }
            .padding(.vertical, Tokens.Space.s)
        }
    }

    /// S15 "Kết nối" (UI_SCREENS S15, D-304, D-306): not connected → "Kết nối Gmail"; connected → "Gmail: {email}" +
    /// "Ngắt kết nối" (→ S20); `needsReconnect` → warning icon + "Kết nối lại Gmail".
    private var gmailSection: some View {
        Section(header: header("settings.connections")) {
            if !viewModel.gmailAvailable {
                rowText("settings.gmail.soon")
                    .foregroundStyle(Tokens.Colors.textSecondary)   // no GMAIL_CLIENT_ID in this build
            } else if let account = viewModel.gmailAccount {
                if let text = viewModel.gmailAccountText {
                    Text(verbatim: text)
                        .font(Tokens.Fonts.fieldValue)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: Tokens.Size.buttonMinHeight, alignment: .leading)
                }
                if account.status == .needsReconnect {
                    Button { Task { await viewModel.connectGmail() } } label: {
                        Label { Text("settings.gmail.reconnect").font(Tokens.Fonts.fieldValue) } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.Colors.warning)
                        }
                        .foregroundStyle(Tokens.Colors.primary)
                        .frame(maxWidth: .infinity, minHeight: Tokens.Size.buttonMinHeight, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.gmailBusy)
                }
                actionRow("settings.gmail.disconnect", danger: true) { viewModel.pendingConfirm = .gmailDisconnect }
                    .disabled(viewModel.gmailBusy)
            } else {
                actionRow("settings.gmail.connect", danger: false) { Task { await viewModel.connectGmail() } }
                    .disabled(viewModel.gmailBusy)
                Text("settings.gmail.note")
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            if viewModel.gmailBusy {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = viewModel.gmailMessage {
                Label { Text(verbatim: message.text).font(Tokens.Fonts.body) } icon: {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Tokens.Colors.danger)
                }
                .foregroundStyle(Tokens.Colors.textPrimary)
            }
        }
    }

    private var signedInUser: UUID? {
        if case .signedIn(let id) = appState.session { id } else { nil }
    }

    @ViewBuilder private var accountSection: some View {
        Section(header: header("settings.account")) {
            if let plan = appState.entitlement?.plan {
                rowText(plan == .premium ? "settings.plan.premium" : "settings.plan.free")
            }
            if let entitlement = appState.entitlement {                                 // S15 AC7 (1F.8)
                if let limit = entitlement.quotaLimit {
                    Text(verbatim: UserMessage(key: "settings.quota",
                                               args: ["\(entitlement.quotaRemaining)", "\(limit)"]).text)
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                }
                Text(verbatim: UserMessage(key: "settings.quota.reset",
                                           args: [entitlement.resetsAt.formatted(date: .omitted, time: .shortened)]).text)
                    .font(Tokens.Fonts.caption)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            if appState.entitlement?.plan != .premium {
                actionRow("settings.upgrade", danger: false) { showsPaywall = true }      // → S16 (1F.6)
            }
            // TODO(spec): "Quản lý gói" needs StoreKit's manage-subscriptions sheet (a View import, D-015) → later.
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
    .environment(Router())
}

#Preview("Dark, AX5") {
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel(localData: MockLocalDataRepository(), drafts: MockTaskRepository(),
                                                  auth: MockAuthService()))
    }
    .environment(AppState())
    .environment(Router())
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility5)
}
