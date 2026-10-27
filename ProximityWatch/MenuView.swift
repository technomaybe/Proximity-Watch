import ServiceManagement
import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuView: View {
    @ObservedObject var monitor: WatchMonitor
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Proximity Watch").font(.headline)
                Text(monitor.state.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if monitor.isPicking {
                picker
            } else {
                watchSection
                Divider()
                settings
            }

            Divider()

            Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
            HStack {
                Button("Lock now") { monitor.lockNow() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = monitor.watchName {
                HStack {
                    Label(name, systemImage: "applewatch")
                    Spacer()
                    Text(monitor.rssi.map { "\($0) dB" } ?? "No signal")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button("Choose a different watch…") { monitor.startPicking() }
            } else {
                Button("Choose your watch…") { monitor.startPicking() }
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hold your watch right next to the Mac. It should be the strongest signal at the top.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if monitor.nearbyDevices.isEmpty {
                ProgressView("Scanning")
                    .controlSize(.small)
            }
            ForEach(monitor.nearbyDevices.prefix(8)) { device in
                Button { monitor.choose(device) } label: {
                    HStack {
                        Text(device.name)
                        Spacer()
                        Text("\(device.rssi) dB").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button("Cancel") { monitor.stopPicking() }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Lock when my watch walks away", isOn: $monitor.isEnabled)

            Text("Lock when the signal drops below \(Int(monitor.lockThreshold)) dB")
                .font(.callout)
            Slider(value: $monitor.lockThreshold, in: -100...(-50), step: 1)
            Text("Tip: stand where you want it to lock and read the signal above.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Wait \(Int(monitor.lockDelay)) seconds before locking")
                .font(.callout)
            Slider(value: $monitor.lockDelay, in: 3...60, step: 1)
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Open at login change failed: \(error)")
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}
