import Foundation
import Observation

/// S13 Places (UI_SCREENS S13, spec §6.9). Search on device; "Lưu địa điểm" / "Chỉ đường" open S04 (place.create /
/// place.open) — nothing is saved or opened before "Xác nhận" (D-100).
@Observable @MainActor final class PlacesViewModel {
    struct SavedRow: Identifiable, Hashable {
        let id: UUID
        let symbol: String          // house / briefcase / mappin
        let title: String           // "Nhà" / "Chỗ làm" / custom label
        let place: PlaceResult
    }

    var query = ""
    private(set) var results: [PlaceResult] = []
    private(set) var searched = false
    private(set) var isSearching = false
    /// The map preview card.
    var selected: PlaceResult?
    private(set) var saved: [SavedRow] = []
    /// Set by "Lưu địa điểm" / "Chỉ đường": the View opens S04.
    private(set) var reviewDraftId: UUID?

    private let places: any PlacesService
    private let localData: any LocalDataRepository
    private let engine: TaskEngine

    init(places: any PlacesService, localData: any LocalDataRepository, engine: TaskEngine) {
        self.places = places
        self.localData = localData
        self.engine = engine
    }

    var showsNoResults: Bool { searched && !isSearching && results.isEmpty }

    func loadSaved() {
        saved = localData.savedPlaces().map { p in
            let (symbol, title): (String, String) = switch p.label {
            case "home": ("house", UserMessage(key: "option.label.home").text)
            case "work": ("briefcase", UserMessage(key: "option.label.work").text)
            default: ("mappin", p.customLabel ?? p.name)
            }
            return SavedRow(id: p.id, symbol: symbol, title: title,
                            place: PlaceResult(name: p.name, address: p.address,
                                               coordinate: Coordinate(latitude: p.latitude, longitude: p.longitude)))
        }
    }

    /// Search field "submit" (on device, no quota).
    // TODO(spec): S13 does not ask for location; searches are not biased to the user's position (D-185: ask on first use).
    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { results = []; searched = false; return }
        isSearching = true
        results = (try? await places.search(text, near: nil)) ?? []
        isSearching = false
        searched = true
        selected = nil
    }

    func select(_ place: PlaceResult) { selected = place }

    /// "Lưu địa điểm" → S04 place.create (the label is chosen there).
    func save() { open(.create) }

    /// "Chỉ đường" → S04 place.open with the preferred maps app (S15).
    func directions() { open(.open) }

    func didOpenReview() { reviewDraftId = nil }

    private func open(_ operation: TaskOperation) {
        guard let selected,
              let draft = engine.startDraft(from: selected, operation: operation,
                                            mapsApp: localData.settings().preferredMapsApp) else { return }
        reviewDraftId = draft.id
    }
}
