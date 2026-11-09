import SwiftUI

/// A short bottom notice (UI_SCREENS §2): 4 s, 8 s while VoiceOver runs, announced to VoiceOver;
/// optional "Hoàn tác" (D-107).
struct ToastModel: Identifiable {
    let id = UUID()
    var message: UserMessage
    var undo: (@MainActor () -> Void)?
}

struct Toast: View {
    let model: ToastModel
    var onUndo: () -> Void = {}

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Text(verbatim: model.message.text)
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if model.undo != nil {
                Spacer(minLength: Tokens.Space.s)
                TextLinkButton("common.undo", action: onUndo)
            }
        }
        .padding(.horizontal, Tokens.Space.l)
        .padding(.vertical, Tokens.Space.s)
        .frame(minHeight: Tokens.Size.buttonMinHeight)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(Tokens.Colors.border, lineWidth: 1))
        .padding(.horizontal, Tokens.Space.screenPadding)
    }
}

extension View {
    /// Shows `model` at the bottom until it times out or "Hoàn tác" is tapped; then sets it back to nil.
    func toast(_ model: Binding<ToastModel?>) -> some View {
        modifier(ToastPresenter(model: model))
    }
}

private struct ToastPresenter: ViewModifier {
    @Binding var model: ToastModel?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let current = model {
                    Toast(model: current) {
                        current.undo?()
                        model = nil
                    }
                    .padding(.bottom, Tokens.Space.l)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: current.id) {
                        AccessibilityNotification.Announcement(current.message.text).post()
                        try? await Task.sleep(for: .seconds(voiceOver ? 8 : 4))
                        if model?.id == current.id { model = nil }
                    }
                }
            }
            .animation(.default, value: model?.id)
    }
}

#Preview("Light") {
    ToastPreview()
}

#Preview("Dark") {
    ToastPreview().preferredColorScheme(.dark)
}

private struct ToastPreview: View {
    @State private var model: ToastModel? = ToastModel(message: UserMessage(key: "common.saved"), undo: {})

    var body: some View {
        VStack(spacing: Tokens.Space.l) {
            DemoDataBadge()
            Toast(model: ToastModel(message: UserMessage(key: "common.saved")))
            Toast(model: ToastModel(message: UserMessage(key: "common.saved"), undo: {}))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Colors.bg)
        .toast($model)
    }
}
