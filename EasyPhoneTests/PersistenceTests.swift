import Testing
@testable import EasyPhoneAI

@Suite("Persistence (DATA_MODEL §12)")
struct PersistenceTests {
    @Test func inMemoryContainerOpens() throws {
        _ = try ModelContainerFactory.make(inMemory: true)
    }
}
