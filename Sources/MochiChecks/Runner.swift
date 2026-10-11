/// Tiny check harness: `check` names a group of expectations, `expect` records failures.
@MainActor enum Runner {
    static var failures: [String] = []
    static var current = ""
}

@MainActor func expect(_ condition: Bool, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !condition {
        Runner.failures.append("✗ \(Runner.current): \(message()) (\(file):\(line))")
    }
}

@MainActor func check(_ name: String, _ body: () throws -> Void) {
    Runner.current = name
    let before = Runner.failures.count
    do { try body() } catch { Runner.failures.append("✗ \(name): threw \(error)") }
    print(Runner.failures.count == before ? "✓ \(name)" : "✗ \(name)")
}
