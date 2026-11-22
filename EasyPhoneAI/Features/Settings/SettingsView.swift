import SwiftUI

/// S15 Settings (UI_SCREENS S15, regrouped by D-317): a short first screen of groups; each group is its own page.
struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    @Environment(AppState.self) private var appState
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appEnv) private var env
    @State private var showsPaywall = false
    @State private var legal: LegalView.Document?

    /// Owner 2026-11-18 (D-317): the first screen lists the groups; each opens its own page (like iOS Settings).
    enum Page: String, CaseIterable, Hashable, Identifiable {
        case account, voice, quickOpen, display, memory, connections, advanced, data, about
        var id: String { rawValue }
        var titleKey: LocalizedStringKey { LocalizedStringKey("settings." + rawValue) }
        var symbol: String {
            switch self {
            case .account: "person.crop.circle.fill"
            case .voice: "waveform"
            case .quickOpen: "hand.tap.fill"
            case .display: "textformat.size"
            case .memory: "heart.text.square.fill"
            case .connections: "envelope.fill"
            case .advanced: "slider.horizontal.3"
            case .data: "externaldrive.fill"
            case .about: "info.circle.fill"
            }
        }
    }

    var body: some View {
        List {
            Group {
                Section { row(.account, summary: accountSummary) }
                Section {
                    row(.voice, summary: nil)
                    row(.quickOpen, summary: UserMessage(key: "settings.quickOpen.summary").text)   // D-325
                    row(.display, summary: UserMessage(key: viewModel.textSize.labelKey).text)
                    row(.memory, summary: memorySummary)
                    row(.connections, summary: gmailSummary)
                }
                Section {
                    if viewModel.showsAdvanced { row(.advanced, summary: nil) }           // ★ hidden in simple mode (P-40)
                    row(.data, summary: nil)
                    row(.about, summary: viewModel.versionText)
                }
            }
            .listRowBackground(Tokens.Colors.surface)
        }
        .settingsList()
        .navigationTitle(Text("settings.title"))
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
        .accessibilityIdentifier("screen.S15")
    }

    /// One group row: icon tile + title + one-line summary + chevron, ≥ 64pt, opens the page.
    private func row(_ page: Page, summary: String?) -> some View {
        NavigationLink { pageView(page) } label: {
            HStack(spacing: Tokens.Space.m) {
                Image(systemName: page.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.onPrimary)
                    .frame(width: 34, height: 34)
                    .background(Tokens.Colors.primary, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.titleKey)
                        .font(Tokens.Fonts.fieldValue)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    if let summary {
                        Text(verbatim: summary)
                            .font(Tokens.Fonts.body)
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: Tokens.Size.rowMinHeight, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("settings.row.\(page.rawValue)")
    }

    // MARK: - Row summaries

    private var accountSummary: String? {
        guard let entitlement = appState.entitlement else { return nil }
        let plan = UserMessage(key: entitlement.plan == .premium ? "settings.plan.premium" : "settings.plan.free").text
        guard let limit = entitlement.quotaLimit else { return plan }
        return "\(plan) · " + UserMessage(key: "settings.quota.short", args: ["\(entitlement.quotaRemaining)", "\(limit)"]).text
    }

    private var memorySummary: String? {
        viewModel.nicknames.isEmpty ? nil
            : UserMessage(key: "settings.nicknames.count", args: ["\(viewModel.nicknames.count)"]).text
    }

    private var gmailSummary: String? {
        guard viewModel.gmailAvailable else { return nil }
        guard let account = viewModel.gmailAccount else { return UserMessage(key: "settings.gmail.notConnected").text }
        return account.status == .needsReconnect ? UserMessage(key: "settings.gmail.reconnect").text : account.email
    }

    // MARK: - Pages

    @ViewBuilder private func pageView(_ page: Page) -> some View {
        @Bindable var settings = viewModel.settings
        List {
            Group {
                switch page {
                case .account: accountPage
                case .voice: voicePage(settings: $settings)
                case .quickOpen: quickOpenPage
                case .display: displayPage(settings: $settings)
                case .memory: memoryPage
                case .connections: gmailSection
                case .advanced:
                    advancedPage(settings: $settings)
                    latencySection
                    permissionsSection
                case .data: dataPage(settings: $settings)
                case .about: aboutPage
                }
            }
            .listRowBackground(Tokens.Colors.surface)
        }
        .settingsList()
        .navigationTitle(Text(page.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.pendingConfirm) { confirm in
            ConfirmSheet(titleKey: LocalizedStringKey(confirm.titleKey), bodyKey: LocalizedStringKey(confirm.bodyKey),
                         // S20: the App Store subscription is not cancelled by deleting the account (API_CONTRACT §6.3).
                         noteKey: confirm == .deleteAccount ? "confirm.deleteAccount.subNote" : nil,
                         confirmKey: LocalizedStringKey(confirm.confirmKey),
                         cancelKey: confirm == .deleteAccount ? "confirm.deleteAccount.no" : "common.cancel",
                         onConfirm: { Task { await viewModel.perform(confirm) } },
                         onCancel: { viewModel.pendingConfirm = nil })
        }
        .sheet(item: $legal) { LegalView(document: $0) }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(viewModel: PaywallViewModel(purchases: env.purchases, api: env.api, userId: signedInUser,
                                                    onPlan: { appState.apply(me: $0) }))
        }
        .accessibilityIdentifier("screen.S15.\(page.rawValue)")
    }

    @ViewBuilder private func voicePage(settings: Bindable<AppSettings>) -> some View {
        Section {
            Toggle(isOn: settings.voiceEnabled) { rowText("settings.voice.enabled") }
                .onChange(of: settings.wrappedValue.voiceEnabled) { viewModel.save() }
                .frame(minHeight: Tokens.Size.buttonMinHeight)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                rowText("settings.voice.rate")
                Slider(value: settings.speechRate, in: 0.3...0.6) {
                    Text("settings.voice.rate")
                } minimumValueLabel: {
                    Text("settings.voice.rate.slow").font(Tokens.Fonts.label)
                } maximumValueLabel: {
                    Text("settings.voice.rate.fast").font(Tokens.Fonts.label)
                } onEditingChanged: { editing in if !editing { viewModel.save() } }
            }
            .padding(.vertical, Tokens.Space.s)
            // TODO(spec): range of the rate slider is not specified; 0.3–0.6 around the 0.45 default (DATA_MODEL §5).
            // D-324 (owner 2026-11-20): voice + pitch. TODO(spec): rows not in UI_SCREENS S15.
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                rowText("settings.voice.pitch")
                Slider(value: settings.ttsPitch, in: 0.8...1.4) {
                    Text("settings.voice.pitch")
                } minimumValueLabel: {
                    Text("settings.voice.pitch.low").font(Tokens.Fonts.label)
                } maximumValueLabel: {
                    Text("settings.voice.pitch.high").font(Tokens.Fonts.label)
                } onEditingChanged: { editing in
                    if !editing { viewModel.save(); Task { await viewModel.testVoice() } }   // hear it at once
                }
            }
            .padding(.vertical, Tokens.Space.s)
            SecondaryButton("settings.voice.test", systemImage: "speaker.wave.2") {
                Task { await viewModel.testVoice() }
            }
            .padding(.vertical, Tokens.Space.s)
        }
        Section {
            voiceRow(nil, label: UserMessage(key: "settings.voice.default").text)
            ForEach(viewModel.voices) { voice in
                voiceRow(voice.id, label: SettingsViewModel.voiceLabel(voice))
            }
        } header: { header("settings.voice.choice") }
        Section {
            Text("settings.voice.download")                                                  // D-324
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Tokens.Space.xs)
        }
        .onAppear { viewModel.loadVoices() }
        Section {
            toggleRow("settings.autoSend", note: "settings.autoSend.note", isOn: settings.autoSend)      // D-296
            toggleRow("settings.handsFree", note: "settings.handsFree.note", isOn: settings.handsFree)   // D-312
        }
    }

    /// D-324: one radio row per installed Vietnamese voice (a Picker clipped its value at AX5); tap = choose + hear it.
    private func voiceRow(_ id: String?, label: String) -> some View {
        let selected = viewModel.selectedVoiceId == id
        return Button {
            viewModel.selectedVoiceId = id
            Task { await viewModel.testVoice() }
        } label: {
            HStack(spacing: Tokens.Space.m) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Tokens.Colors.primary : Tokens.Colors.border)
                    .accessibilityHidden(true)
                Text(verbatim: label)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Tokens.Size.buttonMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("settings.voice.\(id ?? "default")")
    }

    /// D-325: how to call Khoai over any screen (Back Tap → "Khoai nghe"). Apple lets no app create a shortcut or
    /// set Back Tap itself, so: one tap to add the shared shortcut, then the Back Tap steps. TODO(spec): not in UI_SCREENS.
    @ViewBuilder private var quickOpenPage: some View {
        Section {
            Text("settings.quickOpen.intro")
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Tokens.Space.xs)
        }
        Section(header: header("settings.quickOpen.step1")) {
            if let url = KhoaiShortcut.iCloudURL {
                PrimaryButton("settings.quickOpen.add") { openURL(url) }
                    .padding(.vertical, Tokens.Space.s)
                stepText("settings.quickOpen.add.note")
            } else {
                stepText("settings.quickOpen.manual")
            }
        }
        Section(header: header("settings.quickOpen.step2")) {
            stepText("settings.quickOpen.backTap")
        }
        Section {
            stepText("settings.quickOpen.other")
        }
    }

    private func stepText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Tokens.Fonts.body)
            .foregroundStyle(Tokens.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Tokens.Space.xs)
    }

    @ViewBuilder private func displayPage(settings: Bindable<AppSettings>) -> some View {
        Section(header: header("settings.textSize"), footer: Text("settings.textSize.note")) {   // D-318
            ForEach(AppTextSize.allCases) { size in
                Button { viewModel.setTextSize(size) } label: {
                    HStack(spacing: Tokens.Space.m) {
                        Image(systemName: viewModel.textSize == size ? "largecircle.fill.circle" : "circle")
                            .font(.title2)
                            .foregroundStyle(viewModel.textSize == size ? Tokens.Colors.primary : Tokens.Colors.border)
                            .accessibilityHidden(true)
                        Text(LocalizedStringKey(size.labelKey))
                            .font(Tokens.Fonts.fieldValue)
                            .foregroundStyle(Tokens.Colors.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Tokens.Size.buttonMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(viewModel.textSize == size ? [.isSelected] : [])
                .accessibilityIdentifier("settings.textSize.\(size.rawValue)")
            }
            // Preview at the chosen size (the whole app already follows it).
            Text("settings.textSize.preview")
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Tokens.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tokens.Colors.honey.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .padding(.vertical, Tokens.Space.s)
        }
        Section {
            toggleRow("settings.simpleMode", note: "settings.simpleMode.note", isOn: settings.simpleMode)
            toggleRow("settings.pet", note: "settings.pet.note", isOn: settings.petEnabled)
        }
    }

    @ViewBuilder private var memoryPage: some View {
        Section(header: header("settings.nicknames")) {
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
        }
        Section {
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
    }

    @ViewBuilder private func advancedPage(settings: Bindable<AppSettings>) -> some View {
        Section {
            toggleRow("settings.autoConfirm", note: "settings.autoConfirm.note", isOn: settings.autoConfirm)  // D-299
            Picker(selection: settings.snoozeMorningHour) {
                ForEach(SettingsViewModel.snoozeHours, id: \.self) { hour in
                    Text(verbatim: UserMessage(key: "settings.snoozeHour.value", args: ["\(hour)"]).text).tag(hour)
                }
            } label: { rowText("settings.snoozeHour") }
            .onChange(of: settings.wrappedValue.snoozeMorningHour) { viewModel.save() }
            .frame(minHeight: Tokens.Size.buttonMinHeight)
            Picker(selection: settings.preferredMapsApp) {
                ForEach(SettingsViewModel.mapsApps, id: \.self) { app in
                    Text(verbatim: FieldFormatter.option(fieldId: "mapsApp", value: app) ?? app).tag(app)
                }
            } label: { rowText("settings.mapsApp") }
            .onChange(of: settings.wrappedValue.preferredMapsApp) { viewModel.save() }
            .frame(minHeight: Tokens.Size.buttonMinHeight)
            #if DEBUG
            NavigationLink { KhoaiPlaygroundView() } label: { rowText("settings.khoaiPlayground") }   // D-327, Debug only
            #endif
        }
    }

    /// D-319: the latest AI timings, so slow parts are measured, not guessed.
    private var latencySection: some View {
        Section(header: header("settings.latency"), footer: Text("settings.latency.note")) {
            if viewModel.latency.isEmpty {
                Text("settings.latency.empty")
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            ForEach(viewModel.latency.prefix(5)) { sample in
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(SettingsViewModel.latencyLabelKey(sample.path)))
                            .font(Tokens.Fonts.fieldValue)
                            .foregroundStyle(Tokens.Colors.textPrimary)
                        Spacer(minLength: Tokens.Space.s)
                        Text(verbatim: UserMessage(key: "settings.latency.total",
                                                   args: [SettingsViewModel.seconds(sample.totalMs)]).text)
                            .font(Tokens.Fonts.fieldValue.bold())
                            .foregroundStyle(Tokens.Colors.textPrimary)
                    }
                    Text(verbatim: UserMessage(key: "settings.latency.detail",
                                               args: [SettingsViewModel.seconds(sample.aiMs),
                                                      SettingsViewModel.seconds(sample.serverOtherMs),
                                                      SettingsViewModel.seconds(sample.networkMs)]).text)
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Tokens.Space.xs)
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear { viewModel.loadLatency() }
    }

    @ViewBuilder private func dataPage(settings: Bindable<AppSettings>) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {          // D-301
                Toggle(isOn: settings.savePhotos) { rowText("settings.savePhotos") }
                    .onChange(of: settings.wrappedValue.savePhotos) { Task { await viewModel.savePhotosChanged() } }
                Text("settings.savePhotos.note")
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            .padding(.vertical, Tokens.Space.xs)
        }
        Section {
            actionRow("settings.clearHistory", danger: true) { viewModel.pendingConfirm = .clearHistory }
            actionRow("settings.clearMemory", danger: true) { viewModel.pendingConfirm = .clearMemory }
        }
    }

    @ViewBuilder private var aboutPage: some View {
        Section {
            Text("settings.aiDisclosure")                        // D-187
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .padding(.vertical, Tokens.Space.s)
        }
        Section {
            actionRow("settings.privacy", danger: false) { legal = .privacy }          // 1G.6 in-app text (D-284)
            actionRow("settings.terms", danger: false) { legal = .terms }
        }
        Section {
            Text(verbatim: viewModel.versionText)
                .font(Tokens.Fonts.caption)
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
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
                    rowText(LocalizedStringKey("perm." + row.capability.rawValue + ".feature"))
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

    @ViewBuilder private var accountPage: some View {
        Section {
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

private extension View {
    /// S15 list look (UI_SCREENS §1.1): inset grouped, `bg` behind, `primary` tint.
    func settingsList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Tokens.Colors.bg)
            .tint(Tokens.Colors.primary)
    }
}
