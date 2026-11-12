import Foundation
import ChatwootModels
import Synchronization

/// Connects to Chatwoot's `RoomChannel` over ActionCable.
///
/// Each call to `updates()` owns one connection for as long as it is iterated: it reconnects
/// with exponential backoff and treats ten seconds of silence as a dead socket, since Chatwoot
/// pings every three. Cancel the iterating task to disconnect.
/// After every `.connected` the consumer should refetch what it shows: events sent while
/// the socket was down are not replayed.
public struct RealtimeClient: Sendable {
    public enum Update: Sendable {
        case connecting
        case connected
        case event(RealtimeEvent)
        /// The server refused the credentials. The stream ends after this.
        case rejected
    }

    private let url: URL
    private let identifier: String
    private let urlSession: URLSession

    static let silenceLimit = Duration.seconds(10)
    static let presenceInterval = Duration.seconds(20)

    public init(server: URL, pubsubToken: String, accountID: Int, userID: Int, urlSession: URLSession = URLSession(configuration: .ephemeral)) {
        var components = URLComponents(url: server.appending(path: "cable"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        url = components.url!
        // ActionCable matches later commands to the subscription by this exact string.
        let channel: [String: any Sendable] = [
            "channel": "RoomChannel", "pubsub_token": pubsubToken, "account_id": accountID, "user_id": userID,
        ]
        identifier = String(decoding: try! JSONSerialization.data(withJSONObject: channel, options: .sortedKeys), as: UTF8.self)
        self.urlSession = urlSession
    }

    public func updates() -> AsyncStream<Update> {
        // Unbounded: a dropped event would leave the UI stale with no reconnect to repair it.
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                await run(continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ continuation: AsyncStream<Update>.Continuation) async {
        var attempt = 0
        while !Task.isCancelled {
            continuation.yield(.connecting)
            switch await connect(continuation) {
            case .rejected:
                continuation.yield(.rejected)
                return
            case .dropped(let wasSubscribed):
                attempt = wasSubscribed ? 0 : attempt + 1
                try? await Task.sleep(for: Self.backoff(attempt: attempt))
            }
        }
    }

    private enum Outcome {
        case rejected
        case dropped(wasSubscribed: Bool)
    }

    /// Runs one socket until it fails, goes quiet, is refused, or the task is cancelled.
    private func connect(_ continuation: AsyncStream<Update>.Continuation) async -> Outcome {
        let socket = urlSession.webSocketTask(with: url)
        let state = ConnectionState()
        socket.resume()

        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await receive(from: socket, state: state, continuation: continuation) }
                group.addTask { await watchSilence(state: state) }
                group.addTask { await keepPresence(over: socket) }
                await group.next()
                // A pending `receive()` ignores task cancellation; closing the socket is what ends it.
                socket.cancel(with: .goingAway, reason: nil)
                group.cancelAll()
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }

        return state.value.withLock { $0.wasRejected ? .rejected : .dropped(wasSubscribed: $0.isSubscribed) }
    }

    private func receive(from socket: URLSessionWebSocketTask, state: ConnectionState, continuation: AsyncStream<Update>.Continuation) async {
        while !Task.isCancelled {
            guard let message = try? await socket.receive() else { return }
            state.value.withLock { $0.lastFrameAt = .now }
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
                state.value.withLock { $0.isSubscribed = true }
                continuation.yield(.connected)
            case .event(let event):
                continuation.yield(.event(event))
            case .rejected, .disconnect(reconnect: false):
                state.value.withLock { $0.wasRejected = true }
                return
            case .disconnect(reconnect: true):
                return
            case .ping, .ignored:
                break
            }
        }
    }

    private func watchSilence(state: ConnectionState) async {
        while !Task.isCancelled, state.value.withLock({ $0.lastFrameAt.duration(to: .now) }) < Self.silenceLimit {
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

/// Shared by the receive loop and the watchdog of one connection.
private final class ConnectionState: Sendable {
    struct Value {
        var lastFrameAt = ContinuousClock.now
        var isSubscribed = false
        var wasRejected = false
    }

    let value = Mutex(Value())
}
