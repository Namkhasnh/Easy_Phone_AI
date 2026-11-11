import Foundation
import Observation

/// S14 History (UI_SCREENS S14, spec §6.10 AC1–AC2, DATA_MODEL §8, D-244).
@Observable @MainActor final class HistoryViewModel {
    typealias Row = DraftRow

    struct Section: Identifiable, Hashable {
        var id: HistoryGroup { group }
        let group: HistoryGroup
        let rows: [Row]
    }

    private(set) var sections: [Section] = []

    private let repository: any TaskRepository
    private let now: () -> Date
    private let rowBuilder: DraftRowBuilder

    init(repository: any TaskRepository, now: @escaping () -> Date = { .now }, timeZone: TimeZone = .current) {
        self.repository = repository
        self.now = now
        rowBuilder = DraftRowBuilder(now: now, timeZone: timeZone)
    }

    var isEmpty: Bool { sections.isEmpty }

    /// Fixed order (AC1); empty groups are not shown.
    func load() {
        sections = HistoryGroup.allCases.compactMap { group in
            let rows = repository.history(group: group).compactMap(rowBuilder.row)
            return rows.isEmpty ? nil : Section(group: group, rows: rows)
        }
    }

    /// Swipe "Ẩn": hides the draft (`isArchived`); "Xóa lịch sử" deletes instead (S15).
    func hide(_ draftId: UUID) {
        guard let draft = repository.draft(draftId) else { return }
        draft.isArchived = true
        draft.updatedAt = now()
        repository.save(draft)
        load()
    }
}
