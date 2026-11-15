import UIKit

/// D-293: `UIApplication.open` / `canOpenURL` (and the pasteboard) only here, behind `SystemService`.
// TODO(decision): D-293 names `UIApplication.open` / `canOpenURL`; `UIPasteboard` (S07 copy) is used the same way.
final class LiveSystemService: SystemService {
    @MainActor func open(_ url: URL) async -> Bool { await UIApplication.shared.open(url) }
    @MainActor func canOpen(_ url: URL) async -> Bool { UIApplication.shared.canOpenURL(url) }
    @MainActor func copy(_ text: String) async { UIPasteboard.general.string = text }
}
