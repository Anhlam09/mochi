import Foundation

// Run with `swift run MochiChecks`. Exits non-zero if any check fails.
runAllChecks()

if Runner.failures.isEmpty {
    print("\nAll checks passed.")
    exit(0)
} else {
    print("\n\(Runner.failures.count) failure(s):")
    Runner.failures.forEach { print($0) }
    exit(1)
}
