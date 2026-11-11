import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.13a — spec §6.9 AC2–AC3, DATA_MODEL §1.6 / §3.5, D-102, D-105.
@MainActor
@Suite("PlacesService + PlaceExecutor")
struct PlaceExecutorTests {
    static let now = Validator.parseDateTime("2026-11-12T09:00:00+07:00")!
    static let benThanh = PlaceResult(name: "Chợ Bến Thành", address: "Lê Lợi, Quận 1, TP.HCM",
                                      coordinate: Coordinate(latitude: 10.772461, longitude: 106.698055))
    let repo = MockTaskRepository()
    let local = MockLocalDataRepository()
    let places = MockPlacesService([benThanh])

    func run(_ op: TaskOperation, _ extra: [String: String]) async -> TaskDraft {
        var values = ["query": "chợ Bến Thành", "name": Self.benThanh.name, "address": Self.benThanh.address,
                      "coordinate": Self.benThanh.coordinate.encoded]
        values.merge(extra) { _, n in n }
        let fields = FieldCatalog.mvp.fields(.place, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .device(origin: "maps"), deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .text, originalInput: "x", steps: [TaskStep(order: 0, kind: .place, operation: op, fields: fields)])
        repo.save(d)
        let e = TaskEngine(repository: repo, executors: [.place: PlaceExecutor(places: places, localData: local)], now: { Self.now })
        e.revalidate(stepId: d.steps[0].id, in: d)
        _ = await e.confirm(stepId: d.steps[0].id, in: d)
        return d
    }

    @Test func coordinateEncoding() {
        #expect(Coordinate(encoded: "10.7769,106.7009") == Coordinate(latitude: 10.7769, longitude: 106.7009))
        #expect(Coordinate(encoded: "91,0") == nil && Coordinate(encoded: "abc") == nil)
        #expect(Self.benThanh.coordinate.encoded == "10.772461,106.698055")
        #expect(Validator.check(fieldId: "coordinate", value: Self.benThanh.coordinate.encoded,
                                in: TaskStep(order: 0, kind: .place, operation: .open, fields: []), now: Self.now) == nil)
    }

    @Test func mapsURLs() {
        #expect(MapsURL.apple(Self.benThanh)?.absoluteString.hasPrefix("https://maps.apple.com/?daddr=10.772461,106.698055") == true)
        #expect(MapsURL.google(Self.benThanh)?.scheme == "comgooglemaps")
    }

    @Test func saveAsHomeIsVerifiedAndIdempotent() async throws {
        let d = await run(.create, ["label": "home"])
        let step = d.steps[0]
        #expect(step.state == .succeeded)
        #expect(step.resultEvidence == "local:place:\(step.id.uuidString)")
        let saved = try #require(local.savedPlaces().first)
        #expect(saved.label == "home" && saved.name == "Chợ Bến Thành" && saved.latitude == 10.772461)
        // A second "Nhà" replaces the first (one home).
        _ = await run(.create, ["label": "home", "name": "Nhà mới"])
        #expect(local.savedPlaces().filter { $0.label == "home" }.map(\.name) == ["Nhà mới"])
    }

    @Test func customLabelIsStored() async {
        _ = await run(.create, ["label": "custom", "customLabel": "Nhà con gái"])
        #expect(local.savedPlaces().first?.customLabel == "Nhà con gái")
    }

    @Test func directionsAreHandedOffNeverSucceeded() async {                // D-102
        let d = await run(.open, ["mapsApp": "googleMaps"])
        #expect(d.steps[0].state == .handedOff && d.steps[0].resultEvidence == nil)
        #expect(d.steps[0].handoffNote == "Cần xem đường đi trong Google Maps")
        #expect(places.opened.first?.app == .googleMaps)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: TaskEngine(repository: repo), permissions: MockPermissionManager())
        #expect(vm.resultCard?.message == "Đường đi đã được mở trong Google Maps.")
    }

    @Test func mockSearchIsDiacriticInsensitive() async throws {
        #expect(try await places.search("cho ben thanh", near: nil).map(\.name) == ["Chợ Bến Thành"])
        #expect(try await places.search("", near: nil).isEmpty)
    }
}
