import ChatwootModels
import Foundation

extension Attachment {
    /// A one-word stand-in for a message that is only an attachment.
    var summary: String {
        switch kind {
        case .image: String(localized: "Photo")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .location: String(localized: "Location")
        default: fileName
        }
    }
}
