import AppIntents
import Foundation

/// D-170 – D-172, ARCHITECTURE §2.2: the one shared entry intent. Compiled into the app **and** the widget extension
/// (folder `Shared/`), because a Control Center / Lock Screen control can only open the app with an intent the app
/// also has (owner iPhone 2026-11-18: an `OpenURLIntent` control did nothing on the Lock Screen).
/// Siri, the Action Button, Back Tap and the control run it; iOS opens the app, then `perform` runs in the app.
struct StartListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.listen.title"
    static let description = IntentDescription("intent.listen.desc")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ListenRequests.request()
        return .result()
    }
}

/// The app registers what "start listening" does (sets `AppState.startListeningRequested`); in the widget
/// extension nothing is registered, iOS opens the app and runs `perform` there.
@MainActor enum ListenRequests {
    static var onRequest: (@MainActor () -> Void)?

    static func request() { onRequest?() }
}
