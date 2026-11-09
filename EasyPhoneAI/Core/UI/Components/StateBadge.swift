import SwiftUI

/// SF Symbol + `state.<raw>` text (UI_SCREENS §2, DATA_MODEL §8). Never color alone (D-183).
/// `args` fill `{service}` (prepared) / `{app}` (handedOff). VoiceOver: one element "Trạng thái: {label}" (§9).
struct StateBadge: View {
    let state: TaskState
    var args: [String] = []

    private var label: String { UserMessage(key: state.labelKey, args: args).text }

    private var color: Color {
        switch state {
        case .succeeded, .userMarkedDone: Tokens.Colors.success
        case .failed: Tokens.Colors.danger
        default: Tokens.Colors.textSecondary
        }
    }

    var body: some View {
        Label {
            Text(verbatim: label)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: state.symbolName)
        }
        .font(Tokens.Fonts.label)
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        // TODO(spec): key `a11y.state` is not named in UI_SCREENS §9 (DOC-23).
        .accessibilityLabel(Text(verbatim: UserMessage(key: "a11y.state", args: [label]).text))
    }
}

#Preview("Light") {
    StateBadgePreview()
}

#Preview("Dark, AX5") {
    StateBadgePreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct StateBadgePreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                DemoDataBadge()
                ForEach(TaskState.allCases, id: \.self) { state in
                    StateBadge(state: state, args: state == .prepared ? ["Zalo"] : state == .handedOff ? ["Điện thoại"] : [])
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Colors.bg)
    }
}
