@preconcurrency import ContactsUI
import SwiftUI

/// One contact handed over by the iOS contact picker. 🔒 id + numbers stay on the device (D-056).
struct PickedContact: Sendable, Hashable {
    let id: String
    let displayName: String
    let phones: [PhoneEntry]
}

/// UI_SCREENS S06 "Chọn trong danh bạ" → `CNContactPickerViewController` (D-014: UIKit only through a representable).
/// The system picker runs out of process, so the app needs no Contacts access; it gets only the chosen contact.
/// Presented from a hidden host controller (the picker misbehaves when it is the root of a SwiftUI sheet).
struct ContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (PickedContact) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")   // a number is needed
        DispatchQueue.main.async { host.present(picker, animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, @preconcurrency CNContactPickerDelegate {
        var parent: ContactPickerPresenter

        init(parent: ContactPickerPresenter) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.isPresented = false
            parent.onPick(Self.picked(contact))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }

        static func picked(_ contact: CNContact) -> PickedContact {
            let record = LiveContactsService.record(contact)
            let name = record.displayName.isEmpty
                ? (CNContactFormatter.string(from: contact, style: .fullName) ?? "") : record.displayName
            let phones = contact.isKeyAvailable(CNContactPhoneNumbersKey) ? contact.phoneNumbers.map { labeled in
                PhoneEntry(label: labeled.label.map(CNLabeledValue<CNPhoneNumber>.localizedString(forLabel:)),
                           number: labeled.value.stringValue)
            } : []
            return PickedContact(id: contact.identifier, displayName: name, phones: phones)
        }
    }
}

/// UI_SCREENS S06 limited access (iOS 18): Apple's `ContactAccessButton` searches all contacts for `query` and lets the
/// user share a match with the app; then the caller resolves again. Wrapped here so Views do not import ContactsUI.
struct ContactAccessRow: View {
    let query: String
    let onShared: () -> Void

    var body: some View {
        ContactAccessButton(queryString: query) { _ in onShared() }
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.buttonMinHeight)
    }
}
