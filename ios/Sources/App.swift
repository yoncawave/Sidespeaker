import SwiftUI

@main
struct SidespeakerApp: App {
    @StateObject private var rx = Receiver()
    @AppStorage("latencyMode") private var latencyMode: LatencyMode = .fast

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text("Sidespeaker").font(.largeTitle)
                Text(rx.status).foregroundColor(.secondary).multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Text("Latency mode").font(.subheadline.weight(.semibold))
                    Picker("Latency mode", selection: $latencyMode) {
                        Text("Normal").tag(LatencyMode.normal)
                        Text("Fast").tag(LatencyMode.fast)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(latencyMode == .normal
                        ? "Uses a larger buffer when locked."
                        : "Keeps the same buffer settings when locked.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 284)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .onAppear {
                rx.setLatencyMode(latencyMode)
                rx.start()
            }
            .onChange(of: latencyMode) { mode in rx.setLatencyMode(mode) }
        }
    }
}
