import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("Router (ARCHITECTURE §2.2)")
@MainActor
struct RouterTests {
    @Test func pushAppendsAndPopToRootClears() {
        let router = Router()
        let id = UUID()
        router.push(.history)
        router.push(.review(id))
        #expect(router.path == [.history, .review(id)])
        router.popToRoot()
        #expect(router.path.isEmpty)
    }
}
