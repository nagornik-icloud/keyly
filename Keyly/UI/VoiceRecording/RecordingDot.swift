import SwiftUI

/// The "recording" dot: ONE for the whole product.
///
/// There used to be two: red without pulse in batch mode and white with a pulsing
/// halo in streaming mode. The same process, voice recording, looked different
/// depending on a mode the user picked for a completely different reason.
///
/// Red, not accent: a red dot is the universal sign of an active recording, read
/// without training. The pulse shows the process is ALIVE: a still dot is indistinguishable from
/// a drawn one, especially on frozen pills.
struct RecordingDot: View {
    /// Processing after stop: the dot fades to gray and stops pulsing:
    /// recording is no longer running, and we must not promise otherwise.
    var isActive: Bool = true

    @State private var pulse = false

    var body: some View {
        let color = isActive ? Theme.Colors.recording : Theme.Colors.fgMuted
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 17, height: 17)
                .scaleEffect(pulse && isActive ? 1.2 : 0.8)
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
        }
        .frame(width: 17, height: 17)
        .onAppear {
            guard !KeylyMotion.isReduced else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
