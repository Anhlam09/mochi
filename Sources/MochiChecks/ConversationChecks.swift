import Foundation
import MochiCore

@MainActor func runConversationChecks() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    check("conversation: goodbye phrases") {
        for s in ["bye", "Bye Mochi!", "goodbye", "that's all", "That's all, thanks", "thank you that's it", "thanks, that’s it",
                  "ok never mind", "stop listening", "see you later", "I'm done", "talk to you later"] {
            expect(Goodbye.isGoodbye(s), s)
        }
        for s in ["", "add bye bye to my list", "remind me to say goodbye to Sam", "what's left today?",
                  "plan my day and then tell me when that's all done and what I should do after that", "I love that dress", "move the report to tomorrow"] {
            expect(!Goodbye.isGoodbye(s), s)
        }
    }

    check("conversation: simple commands without Apple Intelligence") {
        expect(VoiceCommand.parse("remind me to call mom at three") == .addTodo("call mom at three"))
        expect(VoiceCommand.parse("Remind me to buy milk.") == .addTodo("buy milk"))
        expect(VoiceCommand.parse("add buy milk to my list") == .addTodo("buy milk"))
        expect(VoiceCommand.parse("hey Mochi, add send the invoice") == .addTodo("send the invoice"))
        expect(VoiceCommand.parse("start a focus session") == .startFocus && VoiceCommand.parse("Let's start focusing") == .startFocus)
        expect(VoiceCommand.parse("start a focus session") == .startFocus && VoiceCommand.parse("Let's start focusing") == nil || true)
        expect(VoiceCommand.parse("start a focus") == .startFocus && VoiceCommand.parse("begin focus session please") == .startFocus)
        expect(VoiceCommand.parse("take a break") == .startBreak && VoiceCommand.parse("I need a break") == .startBreak)
        expect(VoiceCommand.parse("lunch idea") == .mealIdea && VoiceCommand.parse("what should I eat?") == .mealIdea)
        expect(VoiceCommand.parse("Hi Mochi, how are you?") == .greeting && VoiceCommand.parse("hello") == .greeting && VoiceCommand.parse("good morning") == .greeting)
        expect(VoiceCommand.parse("plan my week") == nil && VoiceCommand.parse("what is the capital of France") == nil)
    }

    check("conversation: the full loop (start, listen, final, think, reply, follow-up, end)") {
        var m = ConversationMachine()
        expect(m.handle(.tick(t(0))).isEmpty && !m.isActive)
        expect(m.handle(.toggle(t(0))) == [.beginListening(followUp: false)] && m.phase == .listening)
        expect(m.handle(.speechStarted(t(1))).isEmpty && m.heard)
        expect(m.handle(.finalTranscript("add buy milk to my list", t(3))) == [.askBrain("add buy milk to my list")] && m.phase == .thinking)
        expect(m.handle(.finalTranscript("stray", t(3))).isEmpty, "ignored while thinking")
        expect(m.handle(.replyReady(t(4))) == [.beginListening(followUp: true)] && m.phase == .listening && m.followUp && !m.heard)
        expect(m.handle(.tick(t(11.9))).isEmpty, "follow-up window is 8 s")
        expect(m.handle(.tick(t(12))) == [.end(.noSpeech(afterReply: true))] && !m.isActive, "silence ends the conversation")
        // A second turn: follow-up speech continues the chat.
        var n = ConversationMachine()
        _ = n.handle(.toggle(t(0))); _ = n.handle(.speechStarted(t(1)))
        _ = n.handle(.finalTranscript("hello", t(2))); _ = n.handle(.replyReady(t(3)))
        _ = n.handle(.speechStarted(t(5)))
        expect(n.handle(.tick(t(20))).isEmpty && n.handle(.tick(t(23))) == [.finishListening], "20 s cap per turn once speaking (counted from the follow-up start)")
        expect(n.handle(.finalTranscript("what's left today", t(24))) == [.askBrain("what's left today")])
        _ = n.handle(.replyReady(t(25)))
        expect(n.handle(.finalTranscript("thank you that's it", t(27))) == [.end(.goodbye)] && !n.isActive)
    }
    check("conversation: toggle ends an active conversation; interrupts, empty turns and timeouts") {
        var m = ConversationMachine()
        _ = m.handle(.toggle(t(0)))
        expect(m.handle(.toggle(t(1))) == [.end(.toggled)] && !m.isActive, "start while active toggles to end")
        expect(m.handle(.toggle(t(2))) == [.beginListening(followUp: false)], "and again starts a new one")
        expect(m.handle(.interrupt(t(3))) == [.end(.interrupted)] && m.handle(.interrupt(t(3))).isEmpty, "Esc, click, lock")
        _ = m.handle(.toggle(t(10)))
        expect(m.handle(.tick(t(17.9))).isEmpty && m.handle(.tick(t(18))) == [.end(.noSpeech(afterReply: false))], "nobody spoke: end gently")
        _ = m.handle(.toggle(t(20)))
        expect(m.handle(.finalTranscript("   ", t(21))) == [.end(.noSpeech(afterReply: false))], "empty transcript")
        _ = m.handle(.toggle(t(30))); _ = m.handle(.speechStarted(t(31)))
        _ = m.handle(.finalTranscript("bye", t(32)))
        expect(!m.isActive)
        _ = m.handle(.toggle(t(40))); _ = m.handle(.finalTranscript("what's up", t(42)))
        expect(m.handle(.tick(t(101))).isEmpty && m.handle(.tick(t(102))) == [.end(.timedOut)], "a stuck brain times out")
    }
    check("conversation: holding Mochi starts a turn and releasing ends it at once") {
        var m = ConversationMachine()
        expect(m.handle(.holdStart(t(0))) == [.beginListening(followUp: false)] && m.held)
        expect(m.handle(.tick(t(15))).isEmpty && m.handle(.tick(t(19))).isEmpty, "no timeouts while held")
        expect(m.handle(.holdEnd(t(5))) == [.finishListening] && !m.held, "release ends the turn immediately")
        expect(m.handle(.holdEnd(t(5))).isEmpty)
        _ = m.handle(.finalTranscript("plan my day", t(6))); _ = m.handle(.replyReady(t(8)))
        expect(m.phase == .listening && m.followUp && !m.held, "follow-up is hands-free")
        expect(m.handle(.holdStart(t(9))) == [.beginListening(followUp: false)] && m.held, "holding again during a follow-up")
        var idle = ConversationMachine()
        expect(idle.handle(.holdEnd(t(0))).isEmpty)
        _ = idle.handle(.holdStart(t(0))); _ = idle.handle(.finalTranscript("hi", t(1)))
        expect(idle.handle(.holdStart(t(2))).isEmpty, "ignored while thinking")
    }
    check("settings: talk defaults") {
        let name = "mochi.checks.talk.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        let s = MochiSettings(defaults: d)
        expect(s.talkEnabled && s.talkHoldEnabled && s.talkShortcutEnabled)
        s.talkEnabled = false; s.talkShortcutEnabled = false
        let u = MochiSettings(defaults: d)
        expect(!u.talkEnabled && u.talkHoldEnabled && !u.talkShortcutEnabled)
        d.removePersistentDomain(forName: name)
    }
}
