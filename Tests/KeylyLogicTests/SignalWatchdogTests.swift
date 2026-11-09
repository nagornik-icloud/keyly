import Testing
import Foundation
@testable import KeylyLogic

/// A lost input is distinguished from a pause in speech.
///
/// The watchdog judges in DECIBELS. It used to get a linear level, which
/// arrived with a cutoff "quieter than -60 dB -> flat zero": a quiet room became digital zero,
/// and recording stopped by itself whenever the user paused to think for three seconds. The tests below
/// hold exactly this boundary: "quiet" vs "dead".
@Suite struct SignalWatchdogTests {

    @Test func живойСигналНеТревожит() {
        var watchdog = SignalWatchdog()
        #expect(watchdog.feed(decibels: -14, now: 0) == .ok)
        #expect(watchdog.feed(decibels: -26, now: 10) == .ok)
    }

    /// There was NEVER any sound: this is NOT "the input dropped", it is "access was not granted".
    ///
    /// Seen in practice: macOS answered `.authorized` to the permission query, `record()` returned
    /// `true`, and `coreaudiod` in the same millisecond logged "Client is not granted access to
    /// the input device". The product recorded digital zero for eight seconds, announced "input lost"
    /// (i.e. lied about the cause), sent silence to a paid cloud service and inserted
    /// eleven characters of hallucination into another app's window.
    @Test func звукаНеБылоНиРазуЭтоНеПотеряАОтказДоступа() {
        var watchdog = SignalWatchdog()
        #expect(watchdog.feed(decibels: -160, now: 0) == .ok)
        #expect(watchdog.feed(decibels: -160, now: 7.5) == .ok)
        #expect(watchdog.feed(decibels: -160, now: 8.0) == .neverStarted)
    }

    /// But if there WAS a signal and it disappeared, that is a real input loss: what was recorded before the drop
    /// is worth recognizing, and the user needs a different message.
    @Test func мёртвыйВходПослеЖивогоЭтоПотеря() {
        var watchdog = SignalWatchdog()
        #expect(watchdog.feed(decibels: -30, now: 0) == .ok)
        #expect(watchdog.feed(decibels: -160, now: 1.0) == .ok)
        #expect(watchdog.feed(decibels: -160, now: 8.9) == .ok)
        #expect(watchdog.feed(decibels: -160, now: 9.0) == .lost)
    }

    /// Reset also clears the memory of a live signal: the next recording is judged from scratch,
    /// otherwise an access denial in the second recording would look like a dropout.
    @Test func послеСбросаОтказСноваЧитаетсяКакОтказ() {
        var watchdog = SignalWatchdog()
        _ = watchdog.feed(decibels: -30, now: 0)
        watchdog.reset()
        _ = watchdog.feed(decibels: -160, now: 10)
        #expect(watchdog.feed(decibels: -160, now: 18.0) == .neverStarted)
    }

    /// A pause between phrases is a normal part of dictation: any signal resets the counter,
    /// otherwise the product would stop recording every time the user thinks.
    @Test func сигналСбрасываетСчётчик() {
        var watchdog = SignalWatchdog()
        _ = watchdog.feed(decibels: -160, now: 0)
        _ = watchdog.feed(decibels: -160, now: 5.0)
        #expect(watchdog.feed(decibels: -30, now: 6.0) == .ok)
        #expect(watchdog.feed(decibels: -160, now: 10.0) == .ok)
        #expect(watchdog.feed(decibels: -160, now: 17.9) == .ok)
        // `.lost`, not `.neverStarted`: there already was a live signal at second 6.
        #expect(watchdog.feed(decibels: -160, now: 18.0) == .lost)
    }

    /// The MAIN test of this type: a quiet room and a pause in speech are NOT input loss.
    /// A live microphone gives -50…-70 dB even when everyone is silent; a disconnected one gives the scale floor.
    @Test func тихаяКомнатаИПаузаВРечиНеСчитаютсяПотерей() {
        for quiet in [Float(-45), -55, -65, -80, -100] {
            var watchdog = SignalWatchdog()
            _ = watchdog.feed(decibels: quiet, now: 0)
            #expect(watchdog.feed(decibels: quiet, now: 60) == .ok,
                    "\(quiet) дБ — это тихо, а не мёртвый вход")
        }
    }

    @Test func сбросНачинаетСчётЗаново() {
        var watchdog = SignalWatchdog()
        _ = watchdog.feed(decibels: -160, now: 0)
        watchdog.reset()
        #expect(watchdog.feed(decibels: -160, now: 4.0) == .ok)
    }
}
