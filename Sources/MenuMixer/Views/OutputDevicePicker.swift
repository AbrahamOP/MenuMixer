import SwiftUI
import CoreAudio

struct OutputDevicePicker: View {
    @Binding var selectedDeviceID: AudioDeviceID
    let devices: [OutputAudioDevice]

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)

            Picker("", selection: $selectedDeviceID) {
                ForEach(devices) { device in
                    Text(device.name)
                        .font(.system(size: 11))
                        .tag(device.id)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.04))
        )
    }
}
