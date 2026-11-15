import SwiftUI

/// What S18 shows for one capability (UI_SCREENS S18, D-185).
struct PendingPermission: Sendable, Hashable, Identifiable {
    enum Variant: Sendable, Hashable {
        /// `notDetermined`: explain first, then "Cho phép" shows the system alert.
        case explainer
        /// `denied` / `restricted`: what still works + "Mở Cài đặt".
        case denied
    }

    let capability: Capability
    let variant: Variant
    var id: String { "\(capability.rawValue).\(variant)" }
}

/// S18 Permission explainer / denied (UI_SCREENS S18, D-185). Sheet; stacked Primary + Secondary (D-182).
struct PermissionSheet: View {
    let pending: PendingPermission
    let onAllow: () -> Void
    let onOpenSettings: () -> Void
    let onLater: () -> Void
    /// Denied variant: the capability's fallback (`perm.<c>.fallback`, e.g. "Chọn ảnh có sẵn") instead of "Để sau".
    var onFallback: (() -> Void)? = nil

    private var key: String { pending.capability.rawValue }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Image(systemName: Self.symbol(pending.capability))
                    .font(.system(size: Tokens.Size.iconHero))
                    .foregroundStyle(Tokens.Colors.primary)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(LocalizedStringKey(pending.variant == .explainer ? "perm.\(key).body" : "perm.denied.body"))
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textPrimary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Space.screenPadding)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Tokens.Space.m) {
                switch pending.variant {
                case .explainer:
                    PrimaryButton("perm.allow", action: onAllow)
                case .denied:
                    PrimaryButton("common.openSettings", action: onOpenSettings)
                }
                if pending.variant == .denied, let onFallback {
                    SecondaryButton(LocalizedStringKey("perm.\(key).fallback"), action: onFallback)
                } else {
                    // TODO(spec): other screens have no fallback action yet; "Để sau" is used there.
                    SecondaryButton("common.later", action: onLater)
                }
            }
            .padding(Tokens.Space.screenPadding)
            .background(Tokens.Colors.bg)
        }
        .background(Tokens.Colors.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("screen.S18")
    }

    private var title: String {
        switch pending.variant {
        case .explainer: UserMessage(key: "perm.\(key).title").text
        case .denied:
            // TODO(spec): UI_SCREENS S18 gives no text for `{feature}`; `perm.<c>.feature` is used (PROGRESS DOC-37).
            UserMessage(key: "perm.denied.title", args: [UserMessage(key: "perm.\(key).feature").text]).text
        }
    }

    static func symbol(_ capability: Capability) -> String {
        switch capability {
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.crop.circle"
        case .microphone: "mic"
        case .speech: "waveform"
        case .camera: "camera"
        case .photos: "photo.on.rectangle"
        case .location: "location"
        }
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

private struct PermissionSheetPreview: View {
    let pending: PendingPermission
    var body: some View {
        DemoDataBadge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Colors.bg)
            .sheet(isPresented: .constant(true)) {
                PermissionSheet(pending: pending, onAllow: {}, onOpenSettings: {}, onLater: {})
            }
    }
}

#Preview("Explainer calendar, light") {
    PermissionSheetPreview(pending: PendingPermission(capability: .calendar, variant: .explainer))
}

#Preview("Denied reminders, dark") {
    PermissionSheetPreview(pending: PendingPermission(capability: .reminders, variant: .denied))
        .preferredColorScheme(.dark)
}

#Preview("Explainer contacts, AX5") {
    PermissionSheetPreview(pending: PendingPermission(capability: .contacts, variant: .explainer))
        .dynamicTypeSize(.accessibility5)
}
