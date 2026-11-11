import SwiftUI

// TODO(spec): UI_SCREENS has no keyboard rule. Owner request 2026-11-10: the multi-line fields have no Return-to-close,
// so a tap on empty space or a scroll closes the keyboard. Buttons and the field itself keep their own taps.
extension View {
    /// Put on a screen's `ScrollView`: tap outside the field or drag the content → keyboard closes.
    func dismissesKeyboard(_ focused: FocusState<Bool>.Binding) -> some View {
        modifier(DismissKeyboard(focused: focused))
    }
}

private struct DismissKeyboard: ViewModifier {
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { focused.wrappedValue = false }
    }
}
