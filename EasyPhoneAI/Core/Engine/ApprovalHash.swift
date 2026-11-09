import CryptoKit
import Foundation

/// DATA_MODEL §3.4 approval snapshot hash (D-101).
/// `userConfirmed` stores `hash(step)`; the executor recomputes it right before calling the system framework
/// and refuses to run on a mismatch (`approval.mismatch`, ARCHITECTURE §5.1).
enum ApprovalHash {
    /// `"<kind>|<operation>|<targetRef ?? "">\n"` + ALL fields (device-only included) sorted by id,
    /// each `"<id>=<value ?? "">"`, joined by `"\n"`.
    // TODO(spec): DATA_MODEL §3.4 does not escape "\n" / "=" inside values; implemented verbatim.
    static func canonical(_ step: TaskStep) -> String {
        let header = "\(step.kind.rawValue)|\(step.operation.rawValue)|\(step.targetRef ?? "")\n"
        let body = step.fields
            .sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) }   // byte order, locale-independent
            .map { "\($0.id)=\($0.value ?? "")" }
            .joined(separator: "\n")
        return header + body
    }

    /// SHA256 of the canonical UTF-8 bytes, lowercase hex (64 chars).
    static func hash(_ step: TaskStep) -> String {
        SHA256.hash(data: Data(canonical(step).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// True when the step still matches what the user approved. No stored hash → not approved.
    static func matches(_ step: TaskStep) -> Bool {
        guard let stored = step.approvedSnapshotHash else { return false }
        return stored == hash(step)
    }
}
