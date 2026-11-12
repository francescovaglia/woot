import Foundation
import Testing
@testable import ChatwootAPI
@testable import ChatwootModels

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct ModelDecodingTests {
    @Test func conversationList() throws {
        let page = try JSONDecoder.chatwoot.decode(ConversationPage.self, from: fixture("conversations"))
        #expect(page.counts?.mine == 1)
        #expect(page.conversations.map(\.id) == [511, 510])

        let open = page.conversations[0]
        #expect(open.status == .open)
        #expect(open.unreadCount == 2)
        #expect(open.contact.name == "Maya Patel")
        #expect(open.contact.avatarURL == nil, "an empty thumbnail means no avatar")
        #expect(open.contact.countryCode == "GB")
        #expect(open.contact.location == "Leeds, United Kingdom")
        #expect(open.contact.customAttributes["seats"] == .number(3))
        #expect(open.assignee?.name == "Alex", "available_name wins over name")
        #expect(open.lastMessage?.text == "Can I export a PDF report?")
        #expect(open.agentLastSeenAt != nil)
        #expect(open.contactLastSeenAt == nil, "zero means never seen")
        #expect(open.labels == ["billing"])
    }

    @Test func realtimeShapedConversationFallsBackToMessages() throws {
        let page = try JSONDecoder.chatwoot.decode(ConversationPage.self, from: fixture("conversations"))
        let resolved = page.conversations[1]
        #expect(resolved.status == .resolved)
        #expect(resolved.assignee == nil)
        #expect(resolved.lastMessage?.id == 1500)
    }

    @Test func messages() throws {
        let messages = try AccountAPI(accountID: 1).messages(in: 511).decode(fixture("messages"))
        #expect(messages.map(\.kind) == [.incoming, .outgoing, .outgoing, .activity, .incoming])

        let note = messages[1]
        #expect(note.isPrivate)
        #expect(note.status == .read)
        #expect(note.sender?.kind == .user)

        let image = try #require(messages[2].attachments.first)
        #expect(messages[2].text == nil)
        #expect(image.kind == .image)
        #expect(image.fileName == "export menu.png")
        #expect(image.width == 1170)

        #expect(messages[3].sender == nil)
        #expect(messages[4].isDeleted)
    }

    @Test func profilePrefersTheActiveAccount() throws {
        let profile = try JSONDecoder.chatwoot.decode(Profile.self, from: fixture("profile"))
        #expect(profile.name == "Alex")
        #expect(profile.avatarURL == nil)
        #expect(profile.accessToken == "token-123")
        #expect(profile.activeAccountID == 7)
        #expect(profile.accounts.map(\.availability) == [.offline, .online])
    }

    @Test func unknownEnumValuesDoNotFailDecoding() throws {
        let json = Data(#"{"id":1,"conversation_id":2,"message_type":9,"created_at":1,"status":"queued","attachments":[{"id":3,"file_type":"hologram"}]}"#.utf8)
        let message = try JSONDecoder.chatwoot.decode(Message.self, from: json)
        #expect(message.kind == .activity)
        #expect(message.status == .sent)
        #expect(message.attachments.first?.kind == .file)
    }
}
