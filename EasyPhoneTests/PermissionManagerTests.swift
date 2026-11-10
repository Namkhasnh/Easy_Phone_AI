import AVFoundation
import Contacts
import CoreLocation
import EventKit
import Photos
import Speech
import Testing
@testable import EasyPhoneAI

/// 1C.1a: `PermissionManager` (ARCHITECTURE §4.4, D-185).
struct PermissionManagerTests {
    @Test func usableStatuses() {
        #expect(PermissionStatus.granted.isUsable && PermissionStatus.limited.isUsable && PermissionStatus.writeOnly.isUsable)
        #expect(!PermissionStatus.notDetermined.isUsable && !PermissionStatus.denied.isUsable
                && !PermissionStatus.restricted.isUsable)
    }

    @Test func deniedErrorCode() {
        #expect(ServiceError.permissionDenied(.calendar).code == "permission.calendar.denied")
        #expect(ServiceError.permissionDenied(.contacts).code == "permission.contacts.denied")
    }

    @Test func liveMapsEventKit() {
        #expect(LivePermissionManager.map(EKAuthorizationStatus.fullAccess) == .granted)
        #expect(LivePermissionManager.map(EKAuthorizationStatus.writeOnly) == .writeOnly)
        #expect(LivePermissionManager.map(EKAuthorizationStatus.denied) == .denied)
        #expect(LivePermissionManager.map(EKAuthorizationStatus.restricted) == .restricted)
        #expect(LivePermissionManager.map(EKAuthorizationStatus.notDetermined) == .notDetermined)
    }

    @Test func liveMapsOtherFrameworks() {
        #expect(LivePermissionManager.map(CNAuthorizationStatus.limited) == .limited)
        #expect(LivePermissionManager.map(CNAuthorizationStatus.authorized) == .granted)
        #expect(LivePermissionManager.map(AVAudioApplication.recordPermission.undetermined) == .notDetermined)
        #expect(LivePermissionManager.map(AVAudioApplication.recordPermission.granted) == .granted)
        #expect(LivePermissionManager.map(SFSpeechRecognizerAuthorizationStatus.denied) == .denied)
        #expect(LivePermissionManager.map(AVAuthorizationStatus.restricted) == .restricted)
        #expect(LivePermissionManager.map(PHAuthorizationStatus.limited) == .limited)
        #expect(LivePermissionManager.map(CLAuthorizationStatus.authorizedWhenInUse) == .granted)
        #expect(LivePermissionManager.map(CLAuthorizationStatus.notDetermined) == .notDetermined)
    }

    @Test func mockAsksOnlyOnceLikeIOS() async {
        let m = MockPermissionManager([.calendar: .notDetermined, .contacts: .denied], answer: .granted)
        #expect(m.status(.calendar) == .notDetermined)
        #expect(await m.request(.calendar) == .granted)
        #expect(m.status(.calendar) == .granted)
        #expect(await m.request(.contacts) == .denied)            // denied stays denied → "Mở Cài đặt"
        #expect(m.requested == [.calendar, .contacts])
        #expect(m.status(.camera) == .granted)                    // previews never show S18 by default
    }

    @Test func environmentsCarryAPermissionManager() {
        #expect(AppEnvironment.mock().permissions is MockPermissionManager)
    }
}
