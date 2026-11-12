import Foundation
import Testing
@testable import ChatwootModels
@testable import ChatwootRealtime

@Suite struct CableFrameTests {
    private func frame(_ json: String) throws -> CableFrame {
        try CableFrame(Data(json.utf8))
    }

    @Test func controlFrames() throws {
        guard case .welcome = try frame(#"{"type":"welcome"}"#) else { Issue.record("welcome"); return }
        guard case .ping = try frame(#"{"type":"ping","message":1794495535}"#) else { Issue.record("ping"); return }
        guard case .subscribed = try frame(#"{"identifier":"{}","type":"confirm_subscription"}"#) else { Issue.record("confirm"); return }
        guard case .disconnect(let reconnect) = try frame(#"{"type":"disconnect","reason":"unauthorized","reconnect":false}"#) else {
            Issue.record("disconnect"); return
        }
        #expect(reconnect == false)
    }

    @Test func messageCreated() throws {
        let json = """
        {"identifier":"{}","message":{"event":"message.created","data":{
          "id":1610,"content":"Hello?","conversation_id":511,"message_type":0,"created_at":1794495900,
          "private":false,"echo_id":"e1","sender":{"id":42,"name":"Maya","type":"contact"},
          "conversation":{"assignee_id":1,"unread_count":3},"account_id":1}}}
        """
        guard case .event(.messageCreated(let message)) = try frame(json) else { Issue.record("message"); return }
        #expect(message.conversationID == 511)
        #expect(message.echoID == "e1")
        #expect(message.sender?.kind == .contact)
    }

    @Test func statusChangeCarriesTheConversation() throws {
        let conversations = String(decoding: try fixture("conversations"), as: UTF8.self)
        let page = try JSONSerialization.jsonObject(with: Data(conversations.utf8)) as! [String: [String: Any]]
        let first = (page["data"]!["payload"] as! [Any])[0]
        let data = String(decoding: try JSONSerialization.data(withJSONObject: first), as: UTF8.self)
        let json = #"{"identifier":"{}","message":{"event":"conversation.status_changed","data":"# + data + "}}"
        guard case .event(.conversationChanged(let conversation)) = try frame(json) else { Issue.record("status"); return }
        #expect(conversation.id == 511)
    }

    @Test func typing() throws {
        let json = #"{"message":{"event":"conversation.typing_on","data":{"conversation":{"id":511},"user":{"id":42,"name":"Maya","type":"contact"},"is_private":false,"account_id":1}}}"#
        guard case .event(.typing(let id, let who, let isTyping, let isPrivate)) = try frame(json) else { Issue.record("typing"); return }
        #expect(id == 511 && who.id == 42 && isTyping && !isPrivate)
    }

    @Test func presence() throws {
        let json = #"{"message":{"event":"presence.update","data":{"account_id":1,"users":{"1":"online","2":"busy"},"contacts":{"42":"online"}}}}"#
        guard case .event(.presence(let agents, let contacts)) = try frame(json) else { Issue.record("presence"); return }
        #expect(agents == [1: .online, 2: .busy])
        #expect(contacts == [42: .online])
    }

    @Test func unknownEventsAreIgnored() throws {
        guard case .ignored = try frame(#"{"message":{"event":"notification.created","data":{"notification":{}}}}"#) else {
            Issue.record("ignored"); return
        }
    }

    @Test func backoffGrowsAndCaps() {
        #expect(RealtimeClient.backoff(attempt: 0) == .milliseconds(500))
        #expect(RealtimeClient.backoff(attempt: 1) == .seconds(1))
        #expect(RealtimeClient.backoff(attempt: 4) == .seconds(8))
        #expect(RealtimeClient.backoff(attempt: 40) == .seconds(30))
    }
}
