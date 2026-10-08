import AudioToolbox
import CoreAudio
import SwiftUI

/// The volume of the Mac's current sound output (speakers, headphones, a USB or Bluetooth
/// device), through Core Audio: the same setting the volume keys change. Some outputs, such as
/// many HDMI and DisplayPort monitors, don't let the Mac set their volume; they get no slider.
enum SoundOutput {
    static func defaultDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func name(_ device: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// 0...1, across all channels (as the volume keys set it).
    static func volume(_ device: AudioDeviceID) -> Double? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        settable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    }

    @discardableResult
    static func setVolume(_ value: Double, _ device: AudioDeviceID) -> Bool {
        var level = Float32(min(max(value, 0), 1))
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    static func canMute(_ device: AudioDeviceID) -> Bool {
        settable(device, kAudioDevicePropertyMute)
    }

    @discardableResult
    static func setMuted(_ muted: Bool, _ device: AudioDeviceID) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        var address = address(kAudioDevicePropertyMute)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func settable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}

/// The volume slider's model. Follows the volume keys, the Sound settings and a change of
/// output (headphones plugged in, say) while Sweeply runs.
@MainActor @Observable
final class VolumeModel {
    struct Output: Equatable {
        var name: String
        /// 0...1
        var volume: Double
        var muted: Bool
        var canSetVolume: Bool
        var canMute: Bool
    }

    private(set) var output: Output?

    private let live: Bool
    private var device: AudioDeviceID?
    private var listening = false
    private var deviceListener: AudioObjectPropertyListenerBlock?

    init(output: Output? = nil, live: Bool = true) {
        self.output = output
        self.live = live
    }

    /// Reads the output and starts following its changes. Calling it again only reads.
    func start() {
        guard live else { return }
        if !listening {
            listening = true
            var address = SoundOutput.address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func set(_ volume: Double) {
        guard var output, output.canSetVolume, let device else { return }
        output.volume = volume
        SoundOutput.setVolume(volume, device)
        // Like the volume keys: turning it up unmutes.
        if output.muted, volume > 0, output.canMute, SoundOutput.setMuted(false, device) {
            output.muted = false
        }
        self.output = output
    }

    func toggleMute() {
        guard var output, output.canMute, let device, SoundOutput.setMuted(!output.muted, device) else { return }
        output.muted.toggle()
        self.output = output
    }

    private func refresh() {
        let current = SoundOutput.defaultDevice()
        if current != device {
            stopFollowing()
            device = current
            if let current { follow(current) }
        }
        guard let device, let volume = SoundOutput.volume(device) else {
            output = device.map { Output(name: SoundOutput.name($0) ?? "", volume: 0, muted: false, canSetVolume: false, canMute: false) }
            return
        }
        output = Output(name: SoundOutput.name(device) ?? "", volume: volume, muted: SoundOutput.isMuted(device) ?? false,
                        canSetVolume: SoundOutput.canSetVolume(device), canMute: SoundOutput.canMute(device))
    }

    /// The device's volume and mute, changed by the keys or another app.
    private func follow(_ device: AudioDeviceID) {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = SoundOutput.address(selector)
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
        }
        deviceListener = listener
    }

    private func stopFollowing() {
        guard let device, let deviceListener else { return }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = SoundOutput.address(selector)
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, deviceListener)
        }
        self.deviceListener = nil
    }
}

/// The volume slider for the Mac's sound output.
struct VolumeSlider: View {
    let model: VolumeModel
    let output: VolumeModel.Output

    var body: some View {
        SpeakerSlider(volume: output.volume, muted: output.muted, canMute: output.canMute,
                      set: { model.set($0) }, toggleMute: { model.toggleMute() })
    }
}

/// A monitor's speaker volume, over DDC; muted means turned down to 0.
struct MonitorVolumeSlider: View {
    let model: BrightnessModel
    let display: BrightnessModel.Display

    var body: some View {
        let volume = display.volume ?? 0
        SpeakerSlider(volume: volume, muted: volume == 0, canMute: true,
                      set: { model.setVolume($0, for: display.id) }, toggleMute: { model.toggleMute(display.id) })
    }
}

/// A volume slider: the speaker mutes and unmutes, and the percentage is shown.
struct SpeakerSlider: View {
    let volume: Double
    let muted: Bool
    let canMute: Bool
    let set: (Double) -> Void
    let toggleMute: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toggleMute()
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill")
                    .foregroundStyle(muted ? Color.orange : .secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .disabled(!canMute)
            .help(muted ? Text("Unmute") : Text("Mute"))
            Slider(value: Binding(get: { volume }, set: { set($0) }), in: 0...1)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).frame(width: 20)
            Text(verbatim: "\(Int((volume * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(muted ? .secondary : .primary)
        }
    }
}
