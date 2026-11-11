import Foundation

/// place create (save) / open (directions) — spec §6.9, DATA_MODEL §3.5:
/// create → `SavedPlace` on the phone, re-read → `local:place:<id>`; open → maps app → `handedOff`, never evidence (D-102).
@MainActor final class PlaceExecutor: StepExecutor {
    private let places: any PlacesService
    private let localData: any LocalDataRepository

    nonisolated init(places: any PlacesService, localData: any LocalDataRepository) {
        self.places = places
        self.localData = localData
    }

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        guard let place = Self.place(from: step) else { return .failed(code: "maps.cannotOpen") }
        switch step.operation {
        case .create: return save(step, place)
        case .open: return await directions(step, place)
        default: return .failed(code: "unsupported")
        }
    }

    /// The `SavedPlace` id is the step id: a retry finds the same row instead of saving twice (D-105).
    private func save(_ step: TaskStep, _ place: PlaceResult) -> ExecutionOutcome {
        let id = step.id
        if localData.savedPlaces().contains(where: { $0.id == id }) { return .verified(evidence: Self.evidence(id)) }
        let label = step.field("label")?.value ?? "custom"
        // TODO(spec): §6.9 AC2 does not say whether a second "Nhà" / "Chỗ làm" replaces the first; it does (one each).
        if label == "home" || label == "work" {
            for old in localData.savedPlaces() where old.label == label { localData.delete(old) }
        }
        localData.save(SavedPlace(id: id, label: label,
                                  customLabel: label == "custom" ? step.field("customLabel")?.value : nil,
                                  name: place.name, address: place.address,
                                  latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
        guard localData.savedPlaces().contains(where: { $0.id == id }) else { return .failed(code: "places.saveFailed") }
        return .verified(evidence: Self.evidence(id))
    }

    private func directions(_ step: TaskStep, _ place: PlaceResult) async -> ExecutionOutcome {
        let app = MapsApp(rawValue: step.field("mapsApp")?.value ?? "") ?? .appleMaps
        do {
            try await places.openDirections(to: place, app: app)
            let appName = FieldFormatter.option(fieldId: "mapsApp", value: app.rawValue) ?? app.rawValue
            return .handedOff(note: UserMessage(key: "handoff.note.directions", args: [appName]).text)
        } catch let error as ServiceError {
            return .failed(code: error.code)
        } catch {
            return .failed(code: "maps.cannotOpen")
        }
    }

    static func evidence(_ id: UUID) -> String { "local:place:\(id.uuidString)" }

    static func place(from step: TaskStep) -> PlaceResult? {
        guard let coordinate = step.field("coordinate")?.value.flatMap(Coordinate.init(encoded:)) else { return nil }
        let name = step.field("name")?.value ?? step.field("query")?.value ?? ""
        return PlaceResult(name: name, address: step.field("address")?.value ?? name, coordinate: coordinate)
    }
}
