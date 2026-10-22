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

    public init(reply: String? = nil, isThinking: Bool = false,
                actionsTaken: [String] = [], unavailableReason: String? = nil) {
        self.reply = reply
        self.isThinking = isThinking
        self.actionsTaken = actionsTaken
        self.unavailableReason = unavailableReason
    }
}
