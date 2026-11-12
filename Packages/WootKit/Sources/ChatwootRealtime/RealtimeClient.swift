import Foundation
import ChatwootModels

/// Keeps one ActionCable connection to Chatwoot's `RoomChannel` alive and streams its events.
///
/// Reconnects with exponential backoff and treats ten seconds of silence as a dead socket,
/// since Chatwoot pings every three. After every `.connected` the consumer should refetch
/// whatever it shows: events sent while the socket was down are not replayed.
public actor RealtimeClient {
    public enum Update: Sendable {
        case connecting
        case connected
        case event(RealtimeEvent)
    }

    public nonisolated let updates: AsyncStream<Update>

    private let url: URL
    private let identifier: String
    private let urlSession: URLSession
    private let continuation: AsyncStream<Update>.Continuation
    private var runTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var lastFrameAt = ContinuousClock.now
    private var isSubscribed = false

    private static let silenceLimit = Duration.seconds(10)
    private static let presenceInterval = Duration.seconds(20)

    public init(server: URL, pubsubToken: String, accountID: Int, userID: Int, urlSession: URLSession = .shared) {
        var components = URLComponents(url: server.appending(path: "cable"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        url = components.url!
        // ActionCable matches subscriptions by this exact string, so it is built once.
        let channel: [String: any Sendable] = [
            "channel": "RoomChannel", "pubsub_token": pubsubToken, "account_id": accountID, "user_id": userID,
        ]
        identifier = String(decoding: try! JSONSerialization.data(withJSONObject: channel, options: .sortedKeys), as: UTF8.self)
        self.urlSession = urlSession
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    public func start() {
        guard runTask == nil else { return }
        runTask = Task { await run() }
    }

    public func stop() {
        runTask?.cancel()
        runTask = nil
        // A pending `receive()` doesn't observe task cancellation, closing the socket ends it.
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func run() async {
        var attempt = 0
        while !Task.isCancelled {
            continuation.yield(.connecting)
            let socket = urlSession.webSocketTask(with: url)
            self.socket = socket
            socket.resume()
            let wasConnected = await connection(over: socket)
            socket.cancel(with: .goingAway, reason: nil)
            attempt = wasConnected ? 0 : attempt + 1
            try? await Task.sleep(for: Self.backoff(attempt: attempt))
        }
    }

    /// Runs until the socket fails or goes quiet. Returns whether the subscription was confirmed.
    private func connection(over socket: URLSessionWebSocketTask) async -> Bool {
        lastFrameAt = .now
        isSubscribed = false
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.receive(from: socket) }
            group.addTask { await self.watchSilence() }
            group.addTask { await self.keepPresence(over: socket) }
            await group.next()
            group.cancelAll()
        }
        return isSubscribed
    }

    private func receive(from socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            guard let message = try? await socket.receive() else { return }
            lastFrameAt = .now
            let data = switch message {
            case .data(let data): data
            case .string(let text): Data(text.utf8)
            @unknown default: Data()
            }
            // A frame Woot can't parse is skipped rather than tearing the connection down.
            guard let frame = try? CableFrame(data) else { continue }
            switch frame {
            case .welcome:
                try? await send(["command": "subscribe", "identifier": identifier], over: socket)
            case .subscribed:
                isSubscribed = true
                continuation.yield(.connected)
            case .event(let event):
                continuation.yield(.event(event))
            case .rejected, .disconnect:
                return
            case .ping, .ignored:
                break
            }
        }
    }

    private func watchSilence() async {
        while !Task.isCancelled, lastFrameAt.duration(to: .now) < Self.silenceLimit {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Chatwoot shows an agent as online only while the client keeps announcing itself.
    private func keepPresence(over socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.presenceInterval)
            let action = #"{"action":"update_presence"}"#
            try? await send(["command": "message", "identifier": identifier, "data": action], over: socket)
        }
    }

    private func send(_ command: [String: String], over socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: command)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    static func backoff(attempt: Int) -> Duration {
        attempt == 0 ? .milliseconds(500) : .seconds(min(30, 1 << min(attempt - 1, 5)))
    }
}
