import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.13b — UI_SCREENS S13, spec §6.9, AI_PROMPTS saved-place labels, D-100, D-106.
@MainActor
@Suite("S13 Places + place resolution")
struct PlacesScreenTests {
    static let now = Validator.parseDateTime("2026-11-12T09:00:00+07:00")!
    static let benThanh = PlaceResult(name: "Chợ Bến Thành", address: "Lê Lợi, Quận 1",
                                      coordinate: Coordinate(latitude: 10.772461, longitude: 106.698055))
    static let benThanh2 = PlaceResult(name: "Bến Thành Market Café", address: "Phan Bội Châu, Quận 1",
                                       coordinate: Coordinate(latitude: 10.7731, longitude: 106.6990))
    let repo = MockTaskRepository()
    let local = MockLocalDataRepository()

    @Test func searchSelectAndOpenReviewForDirections() async throws {
        let places = MockPlacesService([Self.benThanh])
        let engine = TaskEngine(repository: repo, executors: [.place: PlaceExecutor(places: places, localData: local)],
                                now: { Self.now })
        let vm = PlacesViewModel(places: places, localData: local, engine: engine)
        vm.query = "cho ben thanh"
        await vm.search()
        #expect(vm.results == [Self.benThanh] && !vm.showsNoResults)
        vm.select(Self.benThanh)
        vm.directions()
        let draft = try #require(vm.reviewDraftId.flatMap(repo.draft))
        let step = draft.steps[0]
        #expect(step.operation == .open && step.state == .awaitingApproval)
        #expect(step.field("mapsApp")?.value == "googleMaps")                 // S15 default (D-298)
        #expect(places.opened.isEmpty)                                         // nothing before "Xác nhận" (D-100)
        _ = await engine.confirm(stepId: step.id, in: draft)
        #expect(places.opened.first?.place == Self.benThanh)
    }

    @Test func saveGoesToReviewWithLabelToChoose() async throws {
        let vm = PlacesViewModel(places: MockPlacesService([Self.benThanh]), localData: local, engine: TaskEngine(repository: repo))
        vm.select(Self.benThanh)
        vm.save()
        let step = try #require(vm.reviewDraftId.flatMap(repo.draft)?.steps.first)
        #expect(step.operation == .create && step.field("label")?.value == nil && step.state == .needsInfo)
        #expect(local.savedPlaces().isEmpty)
    }

    @Test func noResultsAndSavedList() async {
        local.save(SavedPlace(label: "home", name: "Nhà", address: "12 Lê Lợi", latitude: 10.7, longitude: 106.7))
        local.save(SavedPlace(label: "custom", customLabel: "Nhà con gái", name: "Chung cư", address: "Q7", latitude: 10.73, longitude: 106.72))
        let vm = PlacesViewModel(places: MockPlacesService(), localData: local, engine: TaskEngine(repository: repo))
        vm.loadSaved()
        #expect(Set(vm.saved.map(\.title)) == ["Nhà", "Nhà con gái"])
        #expect(vm.saved.first { $0.title == "Nhà" }?.symbol == "house")
        vm.query = "xyz"
        await vm.search()
        #expect(vm.showsNoResults)
    }

    // MARK: - DeviceResolver for place steps

    func resolveDraft(_ query: String, places: MockPlacesService) async -> TaskDraft {
        let e = TaskEngine(repository: repo,
                           resolver: DeviceResolver(contacts: MockContactsService(), calendar: MockCalendarService(),
                                                    permissions: MockPermissionManager(), places: places,
                                                    savedPlaces: { local.savedPlaces() }),
                           now: { Self.now })
        let fields = FieldCatalog.mvp.fields(.place, .open).map {
            Field(id: $0.id, type: $0.type, value: ["query": query, "mapsApp": "appleMaps"][$0.id], source: .ai, deviceOnly: $0.deviceOnly)
        }
        let d = TaskDraft(inputMode: .voice, originalInput: "x", steps: [TaskStep(order: 0, kind: .place, operation: .open, fields: fields)])
        repo.save(d)
        await e.resolveDevice(in: d)
        return d
    }

    func resolve(_ query: String, places: MockPlacesService) async -> TaskStep {
        await resolveDraft(query, places: places).steps[0]
    }

    @Test func homeLabelUsesTheSavedPlace() async {                           // "chỉ đường về nhà" → query "home"
        local.save(SavedPlace(label: "home", name: "Nhà", address: "12 Lê Lợi", latitude: 10.7, longitude: 106.7))
        let step = await resolve("home", places: MockPlacesService([Self.benThanh]))
        #expect(step.field("address")?.value == "12 Lê Lợi")
        #expect(step.field("coordinate")?.value == "10.700000,106.700000")
        #expect(step.field("name")?.source == .device(origin: "savedPlace"))
        #expect(step.state == .awaitingApproval)
    }

    @Test func oneSearchResultFills() async {
        let step = await resolve("chợ Bến Thành", places: MockPlacesService([Self.benThanh]))
        #expect(step.field("name")?.value == "Chợ Bến Thành" && step.state == .awaitingApproval)
    }

    @Test func severalResultsAskAndPickFillsEverything() async throws {
        let places = MockPlacesService([Self.benThanh, Self.benThanh2])
        let d = await resolveDraft("bến thành", places: places)
        let amb = try #require(d.steps[0].field("coordinate")?.ambiguity)
        #expect(amb.kind == .place && amb.question == "Bạn muốn chọn địa điểm nào?" && amb.candidates.count == 2)
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: TaskEngine(repository: repo, now: { Self.now }),
                                 permissions: MockPermissionManager())
        vm.openPendingPicker()
        #expect(vm.pickingFieldId == "coordinate")                              // S06 opens by itself
        await vm.pick(amb.candidates[1], fieldId: "coordinate")
        #expect(vm.step?.field("name")?.value == "Bến Thành Market Café")
        #expect(vm.step?.field("address")?.value == "Phan Bội Châu, Quận 1")
        #expect(vm.blocker == nil)
    }
}
