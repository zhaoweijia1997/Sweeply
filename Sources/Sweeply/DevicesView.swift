import SwiftUI

struct DevicesView: View {
    let model: PeripheralsModel
    let brightness: BrightnessModel

    var body: some View {
        ScrollView {
            if let peripherals = model.peripherals {
                VStack(alignment: .leading, spacing: 20) {
                    section("Displays", systemImage: "display", isEmpty: peripherals.displays.isEmpty) {
                        ForEach(peripherals.displays) { display in
                            VStack(alignment: .leading, spacing: 0) {
                                DeviceRow(
                                    name: display.name.isEmpty ? String(localized: "Display") : display.name,
                                    info: "\(display.pixelWidth) × \(display.pixelHeight) · \(display.refreshRate) Hz",
                                    badge: display.isBuiltIn ? "Built-in" : nil)
                                if let control = brightness.display(display.id) {
                                    Group {
                                        if control.supported {
                                            BrightnessSlider(model: brightness, display: control)
                                        } else {
                                            Text("Brightness can't be controlled for this display.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 12)
                                }
                            }
                        }
                    }
                    section("External drives", systemImage: "externaldrive", isEmpty: peripherals.drives.isEmpty) {
                        ForEach(peripherals.drives) { drive in
                            DriveRow(drive: drive)
                        }
                    }
                    section("USB devices", systemImage: "cable.connector", isEmpty: peripherals.usb.isEmpty) {
                        ForEach(peripherals.usb) { device in
                            DeviceRow(
                                name: device.name,
                                info: [device.vendor, device.speedText].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                    section("Thunderbolt devices", systemImage: "bolt.horizontal", isEmpty: peripherals.thunderbolt.isEmpty) {
                        ForEach(peripherals.thunderbolt) { device in
                            DeviceRow(name: device.name, info: device.vendor ?? "")
                        }
                    }
                    Text("Only names, sizes and speeds are shown. Sweeply never reads what's on external drives, and never shows serial numbers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.start()
            brightness.refresh()
        }
        .onDisappear { model.stop() }
    }

    private func section(
        _ title: LocalizedStringKey, systemImage: String, isEmpty: Bool, @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                if isEmpty {
                    Text("None connected")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    rows()
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        }
    }
}

private struct DeviceRow: View {
    let name: String
    /// Numbers and product names; not translated.
    let info: String
    var badge: LocalizedStringKey?

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: name).fontWeight(.medium)
            if let badge {
                Text(badge)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            Spacer()
            Text(verbatim: info)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
    }
}

private struct DriveRow: View {
    let drive: Peripherals.Drive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(verbatim: drive.name).fontWeight(.medium)
                Text(connection)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                Spacer()
                Text("\(formatBytes(drive.available)) free of \(formatBytes(drive.capacity))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: Double(drive.capacity - drive.available), total: Double(max(drive.capacity, 1)))
            Text(verbatim: drive.format)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var connection: LocalizedStringKey {
        switch drive.connection {
        case .usb: "USB"
        case .thunderbolt: "Thunderbolt"
        case .diskImage: "Disk image"
        case let .other(bus): bus.isEmpty ? "Other" : LocalizedStringKey(stringLiteral: bus)
        }
    }
}
