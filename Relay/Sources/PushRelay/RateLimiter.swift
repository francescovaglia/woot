import Foundation
import Synchronization

/// A fixed one-minute window per key, so a misbehaving server can't flood one phone.
// ponytail: in memory and per process, enough for a single container; move to Redis if the relay scales out.
final class RateLimiter: Sendable {
    private let limit: Int
    private let windows = Mutex<[String: (start: Date, count: Int)]>([:])

    init(perMinute limit: Int) {
        self.limit = limit
    }

    func allow(_ key: String, now: Date = .now) -> Bool {
        windows.withLock { windows in
            if windows.count > 10_000 { windows = windows.filter { now.timeIntervalSince($0.value.start) < 60 } }
            var window = windows[key].flatMap { now.timeIntervalSince($0.start) < 60 ? $0 : nil } ?? (start: now, count: 0)
            window.count += 1
            windows[key] = window
            return window.count <= limit
        }
    }
}
