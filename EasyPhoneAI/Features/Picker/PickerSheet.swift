import SwiftUI

/// S06 Picker (UI_SCREENS S06, D-106 — never auto-pick). Title = `Ambiguity.question`; rows ≥ 72pt with a 44pt
/// initials circle, `title` (`fieldValue`), `subtitle` (masked "•••• 567" or date). No default selection; tapping a row
/// picks and closes (on device, no quota, D-251). No candidates → `picker.noMatch` text.
struct PickerSheet: View {
    let ambiguity: Ambiguity
    /// Contacts only: "Chọn trong danh bạ" (iOS contact picker, 1C.9c).
    var onOpenContacts: (() -> Void)?
    /// Contacts with limited access (iOS 18): `perm.limited.contacts` + Apple's `ContactAccessButton` for this name.
    var limitedQuery: String?
    var onLimitedShared: () -> Void = {}
    let onPick: (Candidate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                Text(verbatim: ambiguity.question)                 // device-built question, keys resolved upstream
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if ambiguity.candidates.isEmpty {
                    // The question already is `picker.noMatch` (DeviceResolver); only the icon is added here.
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: Tokens.Size.iconHero))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(ambiguity.candidates) { candidate in
                    Button {
                        onPick(candidate)
                        dismiss()
                    } label: {
                        CandidateRow(candidate: candidate, showsInitials: ambiguity.kind == .contact)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if onOpenContacts != nil || limitedQuery != nil {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    if let query = limitedQuery {
                        Text("perm.limited.contacts")
                            .font(Tokens.Fonts.body)
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ContactAccessRow(query: query) {
                            onLimitedShared()
                            dismiss()
                        }
                    }
                    if let onOpenContacts {
                        SecondaryButton("picker.openContacts", systemImage: "person.crop.circle") {
                            dismiss()
                            onOpenContacts()
                        }
                    }
                }
                .padding(Tokens.Space.screenPadding)
                .background(Tokens.Colors.bg)
            }
        }
        .background(Tokens.Colors.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("screen.S06")
    }
}

private struct CandidateRow: View {
    let candidate: Candidate
    let showsInitials: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            if showsInitials {
                // TODO(spec): the contact photo (`imageRef`) is not loaded yet; initials are shown.
                Text(verbatim: Self.initials(candidate.title))
                    .font(Tokens.Fonts.label)
                    .foregroundStyle(Tokens.Colors.onHoney)
                    .frame(width: Tokens.Size.tapTargetMin, height: Tokens.Size.tapTargetMin)
                    .background(Tokens.Colors.honey, in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(verbatim: candidate.title)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                if let subtitle = candidate.subtitle {
                    Text(verbatim: subtitle)
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(Tokens.Fonts.label)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(Tokens.Space.m)
        .frame(minHeight: 72)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)                     // "{title}, {subtitle}" (UI_SCREENS §9)
    }

    /// Last word's first letter (Vietnamese given name comes last): "Nguyễn Văn Minh" → "M".
    static func initials(_ name: String) -> String {
        String(name.split(separator: " ").last?.first ?? "?").uppercased()
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

private struct PickerPreview: View {
    let ambiguity: Ambiguity
    var body: some View {
        DemoDataBadge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Colors.bg)
            .sheet(isPresented: .constant(true)) { PickerSheet(ambiguity: ambiguity) { _ in } }
    }
}

#Preview("Contacts, light") {
    PickerPreview(ambiguity: Ambiguity(kind: .contact, question: "Bạn muốn gọi anh Minh nào?", candidates: [
        Candidate(id: "1", title: "Nguyễn Văn Minh", subtitle: nil),
        Candidate(id: "2", title: "Trần Mính", subtitle: "•••• 321"),
    ]))
}

#Preview("Numbers, dark") {
    PickerPreview(ambiguity: Ambiguity(kind: .phoneNumber, question: "Bạn muốn dùng số nào của mẹ?", candidates: [
        Candidate(id: "+84901234567", title: "di động: •••• 567"),
        Candidate(id: "+84912000111", title: "nhà: •••• 111"),
    ]))
    .preferredColorScheme(.dark)
}

#Preview("No match, AX5") {
    PickerPreview(ambiguity: Ambiguity(kind: .contact, question: "Mình chưa tìm thấy người này, bạn chọn trong danh bạ nhé",
                                       candidates: []))
        .dynamicTypeSize(.accessibility5)
}
