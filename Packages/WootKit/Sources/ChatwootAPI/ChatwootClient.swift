import Foundation
import ChatwootModels

/// Sends `Endpoint`s to one Chatwoot server and maps failures to `ChatwootError`.
public struct ChatwootClient: Sendable {
    public let server: URL
    let credential: Credential?
    let urlSession: URLSession

    public init(server: URL, credential: Credential? = nil, urlSession: URLSession = .shared) {
        self.server = server
        self.credential = credential
        self.urlSession = urlSession
    }

    public init(session: ChatwootSession, urlSession: URLSession = .shared) {
        self.init(server: session.server, credential: session.credential, urlSession: urlSession)
    }

    @discardableResult
    public func send<Response>(_ endpoint: Endpoint<Response>) async throws(ChatwootError) -> Response {
        try await sendReturningHeaders(endpoint).0
    }

    /// Like `send`, but also returns the response headers, which carry Devise session tokens.
    func sendReturningHeaders<Response>(_ endpoint: Endpoint<Response>) async throws(ChatwootError) -> (Response, HTTPURLResponse) {
        let (data, response) = try await perform(endpoint)
        try Self.validate(response, data: data)
        do {
            return (try endpoint.decode(data), response)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    private func perform<Response>(_ endpoint: Endpoint<Response>) async throws(ChatwootError) -> (Data, HTTPURLResponse) {
        let request = endpoint.urlRequest(server: server, headers: credential?.headers ?? [:])
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatwootError.transport(.badServerResponse) }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw .offline
            default: throw .transport(error.code)
            }
        } catch let error as ChatwootError {
            throw error
        } catch {
            throw .transport(.unknown)
        }
    }

    static func validate(_ response: HTTPURLResponse, data: Data) throws(ChatwootError) {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw .unauthorized
        default:
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.text
            throw .server(status: response.statusCode, message: message)
        }
    }
}
