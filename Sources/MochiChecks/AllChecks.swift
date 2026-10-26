import MochiCore

/// Entry point for grouped checks. Add new groups here.
@MainActor func runAllChecks() {
    check("bundle ID is stable") {
        expect(MochiCore.bundleID == "com.anh.mochi")
    }
    runEngineChecks()
    runChatterChecks()
    runTodoChecks()
    runBrainChecks()
    runExtrasChecks()
    runConversationChecks()
}
