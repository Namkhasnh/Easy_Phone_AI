import ActivityKit
import Foundation
import OSLog

/// 4H.5: the guide step as a Live Activity (`Shared/GuideActivityAttributes`, drawn by `Widgets/GuideLiveActivity`).
/// One activity at a time; a new guide replaces the old one. Errors are logged (no content, D-059) and ignored.
@MainActor final class LiveGuideProgressService: GuideProgressService {
    private nonisolated static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "guide")

    /// `nonisolated` so `AppEnvironment.mock(.uiTest)` can build it off the main actor (UI tests see the real activity).
    nonisolated init() {}

    func show(_ progress: GuideProgress) {
        let state = GuideActivityAttributes.ContentState(label: progress.label, text: progress.text, step: progress.step,
                                                         total: progress.total)
        // After the panel session's lifetime the Lock Screen shows the step as out of date.
        let content = ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(GuideSessions.lifetime))
        let title = progress.title
        Task { await Self.apply(title: title, content: content) }
    }

    func end() {
        Task { await Self.endAll(except: nil) }
    }

    /// Off the main actor: the `Activity` objects never cross an actor (Swift 6 sending rules).
    private nonisolated static func apply(title: String, content: ActivityContent<GuideActivityAttributes.ContentState>) async {
        if let same = Activity<GuideActivityAttributes>.activities.first(where: { $0.attributes.title == title }) {
            await same.update(content)
            await endAll(except: same.id)
            return
        }
        await endAll(except: nil)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: GuideActivityAttributes(title: title), content: content)
        } catch {
            logger.info("guide activity not started: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private nonisolated static func endAll(except id: String?) async {
        for activity in Activity<GuideActivityAttributes>.activities where activity.id != id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
