import Testing
import Foundation
@testable import KeylyLogic

/// Dictation wave: an EQUALIZER, not a silhouette scaled by loudness.
///
/// These tests exist because two earlier attempts at this wave failed the same way and
/// both were accepted from a SCREENSHOT. A screenshot shows one moment in time: it cannot
/// show that bars move in sync, or that the picture freezes at steady
/// loudness. Both defects were found by watching it live, not from a screenshot.
@Suite struct WaveformMathTests {

    /// The MAIN requirement: at CONSTANT loudness the picture must change over time.
    /// The previous version failed exactly here: the bars just grew taller vertically and
    /// essentially stood still.
    @Test func приРовнойГромкостиВолнаПродолжаетДвигаться() {
        let level: Float = 0.6
        let a = (0..<WaveformMath.barCount).map { WaveformMath.liveHeight(level: level, time: 10.0, index: $0) }
        let b = (0..<WaveformMath.barCount).map { WaveformMath.liveHeight(level: level, time: 10.2, index: $0) }
        let moved = zip(a, b).filter { abs($0 - $1) > 0.5 }.count
        #expect(moved >= WaveformMath.barCount / 2,
                "за 0.2с при той же громкости должна сдвинуться хотя бы половина полосок, сдвинулось \(moved)")
    }

    /// Bars move INDEPENDENTLY: at any moment there is a noticeable spread between them.
    /// If they moved in step, it would read as an animation, not as sound.
    @Test func полоскиНеХодятСтроем() {
        for t in stride(from: 0.0, to: 3.0, by: 0.25) {
            let hs = (0..<WaveformMath.barCount).map { WaveformMath.liveHeight(level: 0.7, time: t, index: $0) }
            let spread = (hs.max() ?? 0) - (hs.min() ?? 0)
            #expect(spread > 3, "в момент \(t) разброс полосок всего \(spread)pt — идут строем")
        }
    }

    /// The pattern does not loop: frequencies are incommensurate, so a frame after a "round" time
    /// does not match the original.
    @Test func рисунокНеПовторяется() {
        let a = (0..<WaveformMath.barCount).map { WaveformMath.liveHeight(level: 0.8, time: 0, index: $0) }
        let b = (0..<WaveformMath.barCount).map { WaveformMath.liveHeight(level: 0.8, time: 1.0, index: $0) }
        let same = zip(a, b).allSatisfy { abs($0 - $1) < 0.1 }
        #expect(!same, "через секунду рисунок совпал — волна зациклилась")
    }

    /// Loudness sets the ENVELOPE: quieter means smaller swings, but motion remains.
    @Test func тихийЗвукДаётМелкоеНоЖивоеШевеление() {
        let quiet: Float = 0.05
        var seen = Set<Int>()
        for t in stride(from: 0.0, to: 2.0, by: 0.1) {
            seen.insert(Int(WaveformMath.liveHeight(level: quiet, time: t, index: 3) * 10))
        }
        #expect(seen.count > 3, "на тихом звуке полоска стоит на месте — вариантов высоты \(seen.count)")

        let loudMax = (0..<40).map { WaveformMath.liveHeight(level: 1.0, time: Double($0) * 0.05, index: 3) }.max() ?? 0
        let quietMax = (0..<40).map { WaveformMath.liveHeight(level: quiet, time: Double($0) * 0.05, index: 3) }.max() ?? 0
        #expect(quietMax < loudMax, "тихий звук должен давать меньший размах, чем громкий")
    }

    /// A dead input is a FLAT LINE: all bars at minimum, no jumps visible.
    @Test func мёртвыйВходЭтоРовнаяЛиния() {
        for t in stride(from: 0.0, to: 2.0, by: 0.3) {
            let hs = (0..<WaveformMath.barCount).map { WaveformMath.liveHeight(level: 0, time: t, index: $0) }
            #expect(hs.allSatisfy { $0 == WaveformMath.minBar }, "в момент \(t) линия не ровная: \(hs)")
        }
    }

    /// Heights never exceed the pill geometry at any loudness and at any moment.
    @Test func высотыВсегдаВГраницах() {
        for t in stride(from: 0.0, to: 5.0, by: 0.13) {
            for level in [Float(0), 0.01, 0.3, 0.75, 1.0] {
                for i in 0..<WaveformMath.barCount {
                    let h = WaveformMath.liveHeight(level: level, time: t, index: i)
                    #expect(h >= WaveformMath.minBar && h <= WaveformMath.maxBar,
                            "полоска \(i) вышла за границы: \(h)")
                }
            }
        }
    }
}
