import Foundation

extension Date {
    /// "now", "5m", "14:32", "Tue", "10 Nov": as short as a list row allows.
    var inboxTimestamp: String {
        let seconds = Date.now.timeIntervalSince(self)
        let calendar = Calendar.current
        if seconds < 60 { return String(localized: "now") }
        if seconds < 3600 { return String(localized: "\(Int(seconds / 60))m") }
        if calendar.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if seconds < 6 * 86_400 { return formatted(.dateTime.weekday(.abbreviated)) }
        return formatted(.dateTime.day().month(.abbreviated))
    }

    /// "Today", "Yesterday", "Tuesday 10 November".
    var daySeparator: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return String(localized: "Today") }
        if calendar.isDateInYesterday(self) { return String(localized: "Yesterday") }
        return formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

extension Int {
    var fileSize: String {
        Int64(self).formatted(.byteCount(style: .file))
    }
}
