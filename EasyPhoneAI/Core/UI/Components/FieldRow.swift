import SwiftUI

/// One field on Review (UI_SCREENS §2, §9). `surface` card, label above value, chevron, ≥ 64pt; tap → editor.
/// Empty → "Chưa có". `needsReview` (D-126) → `warningBg` + `exclamationmark.triangle` + "Kiểm tra lại".
/// OCR source → "Xem ảnh gốc". Ambiguity → its question + "Chọn" (D-106).
/// `displayValue` is the value already formatted for people by the caller (dates, masked numbers…).
struct FieldRow: View {
    let field: Field
    let kind: TaskKind
    let displayValue: String?
    var onEdit: () -> Void = {}
    var onViewSource: () -> Void = {}
    var onChoose: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    private var hasValue: Bool { !(displayValue ?? "").isEmpty }
    private var label: String { String(localized: String.LocalizationValue(field.labelKey(kind: kind))) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Button(action: onEdit) { mainRow }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityText))
                // TODO(spec): key `a11y.field.hint` is not named in UI_SCREENS §9 (DOC-23).
                .accessibilityHint(Text("a11y.field.hint"))

            if field.source.isOCR {
                TextLinkButton("common.viewSourceImage", action: onViewSource)
            }
            if let ambiguity = field.ambiguity {
                Text(verbatim: ambiguity.question)                      // device / backend data, not a UI literal
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryButton("common.choose", action: onChoose)
            }
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, minHeight: Tokens.Size.rowMinHeight, alignment: .leading)
        .background(field.needsReview ? Tokens.Colors.warningBg : Tokens.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .strokeBorder(Tokens.Colors.border, lineWidth: Tokens.Size.borderIncreasedContrast)
            }
        }
    }

    private var mainRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Space.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Space.m))
        return layout {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(verbatim: label)
                    .font(Tokens.Fonts.label)
                    .foregroundStyle(field.needsReview ? Tokens.Colors.warning : Tokens.Colors.textSecondary)
                Group {
                    if hasValue {
                        Text(verbatim: displayValue ?? "")
                            .foregroundStyle(Tokens.Colors.textPrimary)
                    } else {
                        Text("common.empty")
                            .foregroundStyle(field.needsReview ? Tokens.Colors.warning : Tokens.Colors.textSecondary)
                    }
                }
                .font(Tokens.Fonts.fieldValue)
                .fixedSize(horizontal: false, vertical: true)

                if field.needsReview {
                    Label("common.checkAgain", systemImage: "exclamationmark.triangle")
                        .font(Tokens.Fonts.label)
                        .foregroundStyle(Tokens.Colors.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(Tokens.Fonts.label)
                // §1.1: never `textSecondary` on `warningBg`.
                .foregroundStyle(field.needsReview ? Tokens.Colors.warning : Tokens.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    /// "{label}, {value or Chưa có}{, cần kiểm tra lại}" (UI_SCREENS §9).
    private var accessibilityText: String {
        let value = hasValue ? (displayValue ?? "") : String(localized: "common.empty")
        var parts = [label, value]
        if field.needsReview { parts.append(String(localized: "a11y.field.needsReview")) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Light") {
    FieldRowPreview()
}

#Preview("Dark") {
    FieldRowPreview().preferredColorScheme(.dark)
}

#Preview("AX5") {
    FieldRowPreview().dynamicTypeSize(.accessibility5)
}

private struct FieldRowPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.m) {
                DemoDataBadge()
                FieldRow(field: Field(id: "title", type: .text, value: "Uống thuốc"), kind: .reminder,
                         displayValue: "Uống thuốc")
                FieldRow(field: Field(id: "notes", type: .longText), kind: .reminder, displayValue: nil)
                FieldRow(field: Field(id: "dueDate", type: .dateTime, value: "2026-11-09T08:00:00+07:00",
                                      source: .ai, confidence: 0.5),
                         kind: .reminder, displayValue: "Thứ Hai, 09/11 lúc 08:00")
                FieldRow(field: Field(id: "dateTime", type: .dateTime, value: "2026-11-13T14:00:00+07:00",
                                      source: .ocr(span: SourceSpan(start: 0, end: 5)), confidence: 0.9),
                         kind: .ocr, displayValue: "Thứ Sáu, 13/11 lúc 14:00")
                FieldRow(field: Field(id: "recipientName", type: .text, value: "Minh", source: .ai,
                                      ambiguity: Ambiguity(kind: .contact, question: "Bạn muốn nhắn Minh nào?",
                                                           candidates: [])),
                         kind: .sms, displayValue: "Minh")
            }
            .padding(Tokens.Space.screenPadding)
        }
        .background(Tokens.Colors.bg)
    }
}
