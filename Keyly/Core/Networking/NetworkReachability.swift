import Foundation
import Network

/// Whether there is a network — known BEFORE sending a request.
///
/// Without this a missing network surfaced only as a timeout: the user pressed the hotkey,
/// saw "Fixing…" and waited a minute to get a refusal. "No network" within a second is not
/// decoration — it's the difference between "the app told me" and "the app hung".
///
/// The monitor starts once and lives the whole time: an on-demand query answers no sooner than
/// a few hundred milliseconds, and the very first call would answer "unknown".
@MainActor
final class NetworkReachability {
    static let shared = NetworkReachability()

    private let monitor = NWPathMonitor()
    private var isStarted = false
    /// `nil` until the monitor gives its first answer. Distinguishing "no network" from "don't know
    /// yet" is required: blocking an action because of our own unreadiness is not acceptable.
    private var lastStatus: Bool?

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if self.lastStatus != satisfied {
                    Log.info(.app, "Сеть: \(satisfied ? "есть" : "нет")")
                }
                self.lastStatus = satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "keyly.network"))
    }

    /// Whether the network is definitely ABSENT. Unknown is treated as "present": refusing because
    /// we can't measure is worse than letting the request go and getting an honest error.
    var isDefinitelyOffline: Bool {
        lastStatus == false
    }
}
