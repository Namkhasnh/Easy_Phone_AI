import OSLog
import AVFoundation
import Contacts
import CoreLocation
import EventKit
import Photos
import Speech

/// iOS permissions for the 8 capabilities (ARCHITECTURE §4.4, D-185, D-186). Stateless; the `map` functions are
/// pure and unit-tested. Usage descriptions live in `InfoPlist.xcstrings` (vi).
final class LivePermissionManager: PermissionManager {
    func status(_ capability: Capability) -> PermissionStatus {
        switch capability {
        case .calendar: Self.map(EKEventStore.authorizationStatus(for: .event))
        case .reminders: Self.map(EKEventStore.authorizationStatus(for: .reminder))
        case .contacts: Self.map(CNContactStore.authorizationStatus(for: .contacts))
        case .microphone: Self.map(AVAudioApplication.shared.recordPermission)
        case .speech: Self.map(SFSpeechRecognizer.authorizationStatus())
        case .camera: Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .photos: Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .location: Self.map(CLLocationManager().authorizationStatus)
        }
    }

    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "permissions")

    func request(_ capability: Capability) async -> PermissionStatus {
        // Never re-prompt: iOS shows its alert only once; afterwards the answer is "Mở Cài đặt" (D-185).
        guard status(capability) == .notDetermined else { return status(capability) }
        switch capability {
        case .calendar: _ = try? await EKEventStore().requestFullAccessToEvents()
        case .reminders:
            do {
                let ok = try await EKEventStore().requestFullAccessToReminders()
                Self.logger.notice("reminders request answered: \(ok, privacy: .public)")
            } catch {
                Self.logger.error("reminders request failed: \((error as NSError).code, privacy: .public)")
            }
        case .contacts: _ = try? await CNContactStore().requestAccess(for: .contacts)
        case .microphone: _ = await AVAudioApplication.requestRecordPermission()
        case .speech:
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in done.resume() }
            }
        case .camera: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .photos: _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        case .location: await LocationAuthorizer.requestWhenInUse()
        }
        let result = status(capability)
        Self.logger.notice("request \(capability.rawValue, privacy: .public) → \(result.rawValue, privacy: .public), raw reminders \(EKEventStore.authorizationStatus(for: .reminder).rawValue, privacy: .public)")
        return result
    }

    // MARK: - Framework status → PermissionStatus (pure)

    static func map(_ s: EKAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ s: CNAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorized: .granted
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ s: AVAudioApplication.recordPermission) -> PermissionStatus {
        switch s {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ s: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ s: AVAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ s: PHAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorized: .granted
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ s: CLAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

/// `CLLocationManager` answers through its delegate; this waits for the first decided status (When In Use only).
@MainActor private final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var done: CheckedContinuation<Void, Never>?

    static func requestWhenInUse() async {
        let authorizer = LocationAuthorizer()
        await withCheckedContinuation { continuation in
            authorizer.done = continuation
            authorizer.manager.delegate = authorizer
            authorizer.manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }   // the first callback fires before the user answers
            self.done?.resume()
            self.done = nil
        }
    }
}
