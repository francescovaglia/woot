import Foundation

public struct RequestBody: Sendable {
    public let data: Data
    public let contentType: String

    static func json(_ value: some Encodable) -> RequestBody {
        // Only called with request structs and string dictionaries, which always encode.
        RequestBody(data: try! JSONEncoder.chatwoot.encode(value), contentType: "application/json")
    }
}

/// A typed description of one API call. Building it never touches the network,
/// so every request can be inspected in tests.
public struct Endpoint<Response: Sendable>: Sendable {
    public enum Method: String, Sendable {
        case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
    }

    public let method: Method
    public let path: String
    public let query: [URLQueryItem]
    public let body: RequestBody?
    let decode: @Sendable (Data) throws -> Response

    init(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = [],
        body: RequestBody? = nil,
        decode: @escaping @Sendable (Data) throws -> Response
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.decode = decode
    }

    func urlRequest(server: URL, headers: [String: String]) -> URLRequest {
        var components = URLComponents(url: server.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        if let body {
            request.httpBody = body.data
            request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

extension Endpoint where Response: Decodable {
    init(_ method: Method, _ path: String, query: [URLQueryItem] = [], body: RequestBody? = nil) {
        self.init(method, path, query: query, body: body) { try JSONDecoder.chatwoot.decode(Response.self, from: $0) }
    }
}

extension Endpoint where Response == Void {
    init(_ method: Method, _ path: String, query: [URLQueryItem] = [], body: RequestBody? = nil) {
        self.init(method, path, query: query, body: body) { _ in }
    }
}

/// Unwraps Chatwoot's `{"payload": ...}` envelope.
struct Payload<Value: Decodable>: Decodable {
    let payload: Value
}
