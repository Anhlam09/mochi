import MochiCore

@MainActor func runAddRequestChecks() {
    check("add requests: clear asks are recognised with the user's own words") {
        expect(AddRequest.parse("hey can you add 100") == .add("100"))
        expect(AddRequest.parse("can you add go for a walkie") == .add("go for a walkie"))
        expect(AddRequest.parse("Hey Mochi, can you please add Call Sam at 4") == .add("Call Sam at 4"))
        expect(AddRequest.parse("add buy groceries to my list") == .add("buy groceries"))
        expect(AddRequest.parse("remind me to drink water at 3pm") == .add("drink water at 3pm"))
        expect(AddRequest.parse("could you put dentist friday on my list please") == .add("dentist friday"))
        expect(AddRequest.parse("add a to-do to pay rent tomorrow") == .add("pay rent tomorrow"))
    }
    check("add requests: vague asks ask what to add") {
        expect(AddRequest.parse("can you add it") == .needsWhat)
        expect(AddRequest.parse("add") == .needsWhat)
        expect(AddRequest.parse("hey can you add something") == .needsWhat)
    }
    check("add requests: other requests go to the model") {
        expect(AddRequest.parse("plan my day") == nil)
        expect(AddRequest.parse("what's my address") == nil)
        expect(AddRequest.parse("how are you") == nil)
        expect(AddRequest.parse("addition homework is hard") == nil)
        expect(AddRequest.parse("move the report to tomorrow") == nil)
    }
}
