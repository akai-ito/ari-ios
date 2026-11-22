import AriKit
import Foundation
import Testing

@Suite("Still working")
struct StillWorkingTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("says nothing for the first minute, or while something new keeps coming")
    func notYet() {
        #expect(StillWorking.elapsed(since: start, lastHeard: start, at: start + 59) == nil)
        #expect(StillWorking.elapsed(since: start, lastHeard: start + 100, at: start + 120) == nil)
    }

    @Test("says how long once a minute-old turn has been quiet for half a minute")
    func quiet() {
        #expect(
            StillWorking.elapsed(since: start, lastHeard: start + 30, at: start + 60) == "1 min")
        #expect(
            StillWorking.elapsed(since: start, lastHeard: start, at: start + 3 * 60 + 59) == "3 min"
        )
    }

    @Test("counts in whole minutes, then hours and minutes")
    func words() {
        #expect(StillWorking.words(59 * 60) == "59 min")
        #expect(StillWorking.words(60 * 60) == "1 hr")
        #expect(StillWorking.words(65 * 60 + 30) == "1 hr 5 min")
    }
}
