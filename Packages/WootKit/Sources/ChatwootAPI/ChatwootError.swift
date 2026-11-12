import Foundation

public enum ChatwootError: Error, Equatable, Sendable {
    /// The address answers, but it is not a Chatwoot server.
    case notChatwoot
    case invalidCredentials
    /// The credential was accepted once and is no longer valid.
    case unauthorized
    case server(status: Int, message: String?)
    case offline
    case transport(URLError.Code)
    case decoding(String)
}

extension ChatwootError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notChatwoot: String(localized: "That address doesn't look like a Chatwoot server.")
        case .invalidCredentials: String(localized: "Wrong email or password.")
        case .unauthorized: String(localized: "Your session has expired. Sign in again.")
        case .server(_, let message?): message
        case .server(let status, nil): String(localized: "The server returned an error (\(status)).")
        case .offline: String(localized: "You're offline.")
        case .transport: String(localized: "Couldn't reach the server.")
        case .decoding: String(localized: "The server sent a response Woot doesn't understand.")
        }
    }
}

/// Chatwoot reports errors as `{"error": "..."}`, `{"errors": ["..."]}` or `{"message": "..."}`.
struct ErrorBody: Decodable {
    let error: String?
    let errors: [String]?
    let message: String?

    var text: String? { error ?? errors?.first ?? message }
}
