import Foundation
import SwiftUI
import MochiCore

// Entry point. `MOCHI_BRAIN_SELFTEST=1` runs the on-device model self-test headless (no app, no
// windows, no menu bar item, no Dock icon) on a throwaway list and exits; otherwise the normal app runs.
if ProcessInfo.processInfo.environment["MOCHI_BRAIN_SELFTEST"] == "1" {
    let context = BrainSelfTest.makeHeadlessContext()
    BrainSelfTest.run(context: context)
    dispatchMain()
} else {
    MochiApp.main()
}
