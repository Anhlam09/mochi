import Foundation

/// What the "Ask Mochi ✨" section of the to-do card shows. Produced by the app's
/// on-device brain (Apple's FoundationModels; nothing leaves the Mac) and rendered by MochiUI.
public struct AskMochiState: Sendable, Equatable {
    /// Mochi's latest answer, if any.
    public var reply: String?
    /// True while the on-device model is working.
    public var isThinking: Bool
    /// Short confirmations of things Mochi did, e.g. "Added 'call mom' for 3:00 PM ✓".
    public var actionsTaken: [String]
    /// Shown instead of the text field when the on-device model can't be used,
    /// e.g. "Turn on Apple Intelligence to chat with Mochi ✨". Nil when available.
    public var unavailableReason: String?
    /// Optional buttons under the reply that open a web page in the user's browser, only when
    /// tapped (e.g. a recipe search for a meal idea). Mochi itself never goes online.
    public var links: [AskLink]

    public init(reply: String? = nil, isThinking: Bool = false,
                actionsTaken: [String] = [], unavailableReason: String? = nil,
                links: [AskLink] = []) {
        self.reply = reply
        self.isThinking = isThinking
        self.actionsTaken = actionsTaken
        self.unavailableReason = unavailableReason
        self.links = links
    }
}

/// A tappable link shown under a reply, e.g. "🍳 Recipes" → a Google search.
public struct AskLink: Sendable, Equatable, Identifiable {
    public var title: String
    public var url: URL
    public var id: String { title + url.absoluteString }

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}
