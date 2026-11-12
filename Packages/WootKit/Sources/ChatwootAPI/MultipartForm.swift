import Foundation

/// A `multipart/form-data` body, for messages that carry attachments.
struct MultipartForm {
    private let boundary = "woot-\(UUID().uuidString)"
    private var data = Data()

    mutating func append(_ name: String, _ value: String) {
        data.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func append(_ name: String, file: OutgoingMessage.File) {
        // The name ends up inside a header, so anything that could break out of it goes.
        let fileName = file.fileName.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\"" && $0 != "\\" }
            .map(String.init).joined()
        data.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        data.append("Content-Type: \(file.mimeType)\r\n\r\n")
        data.append(file.data)
        data.append("\r\n")
    }

    var body: RequestBody {
        var closed = data
        closed.append("--\(boundary)--\r\n")
        return .init(data: closed, contentType: "multipart/form-data; boundary=\(boundary)")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
