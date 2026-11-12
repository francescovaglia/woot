import Foundation
import ChatwootModels

/// What Chatwoot pushes to an agent over ActionCable, reduced to what a client acts on.
public enum RealtimeEvent: Sendable {
    case messageCreated(Message)
    case messageUpdated(Message)
    case conversationCreated(Conversation)
    /// Status, assignee, labels, read state or contact changed: the payload is the whole conversation.
    case conversationChanged(Conversation)
    case typing(conversationID: Int, participant: Participant, isTyping: Bool, isPrivate: Bool)
    case presence(agents: [Int: Availability], contacts: [Int: Availability])
}

/// One ActionCable frame.
enum CableFrame: Sendable {
    case welcome
    case ping
    case subscribed
    case rejected
    case disconnect(reconnect: Bool)
    case event(RealtimeEvent)
    /// An event this client doesn't handle, such as `notification.created`.
    case ignored

    init(_ data: Data) throws {
        let decoder = JSONDecoder.chatwoot
        let envelope = try decoder.decode(Envelope.self, from: data)
        switch envelope.type {
        case "welcome": self = .welcome
        case "ping": self = .ping
        case "confirm_subscription": self = .subscribed
        case "reject_subscription": self = .rejected
        case "disconnect": self = .disconnect(reconnect: envelope.reconnect ?? true)
        case nil:
            guard let name = try decoder.decode(Broadcast<Discard>.self, from: data).message.event else {
                self = .ignored
                return
            }
            self = try Self.event(named: name, in: data, decoder: decoder).map(CableFrame.event) ?? .ignored
        default:
            self = .ignored
        }
    }

    private static func event(named name: String, in data: Data, decoder: JSONDecoder) throws -> RealtimeEvent? {
        func payload<T: Decodable>(_ type: T.Type) throws -> T {
            try decoder.decode(Broadcast<T>.self, from: data).message.data
        }

        switch name {
        case "message.created":
            return .messageCreated(try payload(Message.self))
        case "message.updated":
            return .messageUpdated(try payload(Message.self))
        case "conversation.created":
            return .conversationCreated(try payload(Conversation.self))
        case "conversation.updated", "conversation.status_changed", "conversation.read",
             "assignee.changed", "team.changed", "conversation.contact_changed":
            return .conversationChanged(try payload(Conversation.self))
        case "conversation.typing_on", "conversation.typing_off":
            let typing = try payload(Typing.self)
            return .typing(
                conversationID: typing.conversation.id,
                participant: typing.user,
                isTyping: name == "conversation.typing_on",
                isPrivate: typing.isPrivate ?? false
            )
        case "presence.update":
            let presence = try payload(Presence.self)
            return .presence(agents: presence.users.availabilities, contacts: presence.contacts?.availabilities ?? [:])
        default:
            return nil
        }
    }
}

private struct Envelope: Decodable {
    let type: String?
    let reconnect: Bool?
}

private struct Broadcast<T: Decodable>: Decodable {
    struct Message: Decodable {
        let event: String?
        let data: T
    }

    let message: Message
}

/// Decodes nothing, so the event name can be read before the payload type is known.
private struct Discard: Decodable {
    init(from decoder: any Decoder) {}
}

private struct Typing: Decodable {
    struct ConversationID: Decodable { let id: Int }

    let conversation: ConversationID
    let user: Participant
    let isPrivate: Bool?

    private enum CodingKeys: String, CodingKey {
        case conversation, user
        case isPrivate = "is_private"
    }
}

private struct Presence: Decodable {
    /// Keys are ids as strings, values are availability names.
    struct Statuses: Decodable {
        let availabilities: [Int: Availability]

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode([String: String].self)
            availabilities = raw.reduce(into: [:]) { result, entry in
                if let id = Int(entry.key), let availability = Availability(rawValue: entry.value) {
                    result[id] = availability
                }
            }
        }
    }

    let users: Statuses
    let contacts: Statuses?
}
