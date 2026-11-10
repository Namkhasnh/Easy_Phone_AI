import SwiftUI

/// S05 Field editor sheet (UI_SCREENS S05). Title = field label; one control per `FieldType`;
/// bottom: PrimaryButton "Lưu" · SecondaryButton "Hủy"; inline validation in `danger` + icon.
struct FieldEditorView: View {
    @State var viewModel: FieldEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    control
                    if let message = viewModel.invalidMessage {
                        Label {
                            Text(verbatim: message.text).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.circle")
                        }
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.danger)
                    }
                }
                .padding(Tokens.Space.screenPadding)
            }
            .background(Tokens.Colors.bg)
            .tint(Tokens.Colors.primary)                       // month arrows; iOS 27 draws the selected day monochrome
            .navigationTitle(Text(LocalizedStringKey(viewModel.titleKey)))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Tokens.Space.m) {
                    PrimaryButton("common.save") {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                    SecondaryButton("common.cancel") { dismiss() }
                }
                .padding(Tokens.Space.screenPadding)
                .background(Tokens.Colors.bg)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .accessibilityIdentifier("screen.S05")
    }

    @ViewBuilder private var control: some View {
        switch viewModel.field.type {
        case .text, .address:
            textControl(axis: .vertical)
            // TODO(spec): `address` → "Tìm trên bản đồ" opens the S13 picker (1C.13).
        case .phone:
            textControl(axis: .horizontal)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        case .longText:
            TextEditor(text: $viewModel.text)
                .font(Tokens.Fonts.fieldValue)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(Tokens.Space.s)
                .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(Tokens.Colors.border))
                .focused($textFocused)
                .onAppear { textFocused = true }
            // TODO(spec): "Đọc to" needs TTSService (1B.3).
            clearButton
        case .dateTime:
            dayChips
            DatePicker(selection: $viewModel.date, displayedComponents: .date) { EmptyView() }
                .datePickerStyle(.graphical)
                .labelsHidden()
            DatePicker(selection: $viewModel.date, displayedComponents: .hourAndMinute) { EmptyView() }
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        case .date:
            DatePicker(selection: $viewModel.date, displayedComponents: .date) { EmptyView() }
                .datePickerStyle(.graphical)
                .labelsHidden()
        case .bool:
            Toggle(isOn: Binding(get: { viewModel.text == "true" },
                                 set: { viewModel.text = $0 ? "true" : "false" })) {
                Text(LocalizedStringKey(viewModel.titleKey))
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
            }
            .tint(Tokens.Colors.primary)
            .frame(minHeight: Tokens.Size.buttonMinHeight)
        case .enumChoice, .durationMinutes:
            choiceList
        case .contactRef, .placeRef, .coordinate:
            // Never edited here: S06 picker (1C.9) / S13 places (1C.13) set these. Review does not open S05 for them.
            EmptyView()
        }
    }

    private func textControl(axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            TextField(text: $viewModel.text, axis: axis) { EmptyView() }
                .font(Tokens.Fonts.fieldValue)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .padding(Tokens.Space.m)
                .frame(minHeight: Tokens.Size.buttonMinHeight)
                .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(Tokens.Colors.border))
                .focused($textFocused)
                .onAppear { textFocused = true }
                .accessibilityLabel(Text(LocalizedStringKey(viewModel.titleKey)))
            clearButton
        }
    }

    @ViewBuilder private var clearButton: some View {
        if !viewModel.text.isEmpty {
            TextLinkButton("editor.clear") { viewModel.clear() }
        }
    }

    /// "Hôm nay" / "Ngày mai" (keep the chosen time).
    private var dayChips: some View {
        HStack(spacing: Tokens.Space.m) {
            SecondaryButton("common.today") { viewModel.setDay(offset: 0) }
            SecondaryButton("common.tomorrow") { viewModel.setDay(offset: 1) }
        }
    }

    /// Radio rows, 64pt, `checkmark` on the chosen one.
    private var choiceList: some View {
        VStack(spacing: Tokens.Space.s) {
            ForEach(viewModel.options, id: \.self) { value in
                let selected = viewModel.text == value
                Button { viewModel.text = value } label: {
                    HStack(spacing: Tokens.Space.m) {
                        Text(verbatim: viewModel.optionLabel(value))
                            .font(Tokens.Fonts.fieldValue)
                            .foregroundStyle(Tokens.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(Tokens.Fonts.label)
                                .foregroundStyle(Tokens.Colors.primary)
                        }
                    }
                    .padding(.horizontal, Tokens.Space.l)
                    .frame(minHeight: Tokens.Size.rowMinHeight)
                    .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                                .strokeBorder(Tokens.Colors.primary, lineWidth: Tokens.Size.borderIncreasedContrast)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Previews (mock data)

@MainActor
private func editorPreview(_ field: Field, kind: TaskKind, op: TaskOperation = .create) -> some View {
    let step = TaskStep(order: 0, kind: kind, operation: op, fields: [field])
    return Color.clear.sheet(isPresented: .constant(true)) {
        FieldEditorView(viewModel: FieldEditorViewModel(field: field, step: step, timeZoneId: "Asia/Ho_Chi_Minh") { _ in })
    }
}

#Preview("Text") {
    editorPreview(Field(id: "title", type: .text, value: "Uống thuốc"), kind: .reminder)
}

#Preview("Date-time, dark") {
    editorPreview(Field(id: "dueDate", type: .dateTime, value: "2099-11-09T08:00:00+07:00"), kind: .reminder)
        .preferredColorScheme(.dark)
}

#Preview("Alert choices") {
    editorPreview(Field(id: "alertMinutesBefore", type: .durationMinutes, value: "60"), kind: .calendarEvent)
}

#Preview("Phone, AX5") {
    editorPreview(Field(id: "phoneNumber", type: .phone, value: "0901 234"), kind: .call, op: .open)
        .dynamicTypeSize(.accessibility5)
}
