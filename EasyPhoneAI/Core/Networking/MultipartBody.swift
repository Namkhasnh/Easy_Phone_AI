import Foundation

/// `multipart/form-data` body for the media uploads (API_CONTRACT §1: `/v1/ocr`, `/v1/transcribe`).
struct MultipartBody: Sendable {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = "easyphone-" + UUID().uuidString.lowercased()) {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, _ content: Data) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(content)
        append("\r\n")
    }

    /// Closes the body; call once, last.
    mutating func finish() -> Data {
        append("--\(boundary)--\r\n")
        return data
    }

    private mutating func append(_ s: String) { data.append(Data(s.utf8)) }
}
