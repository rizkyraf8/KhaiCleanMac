import SwiftUI

/// Picks where a scan runs: Home or another mounted disk. Hidden while there is no other disk.
struct LocationPicker: View {
    @Binding var selection: ScanLocation
    private var volumes: VolumeList { .shared }

    var body: some View {
        HStack {
            if !volumes.volumes.isEmpty || selection.isVolume {
                Picker(L("Lokasi", "Location"), selection: $selection) {
                    ForEach(volumes.locations) { location in
                        Label(location.isVolume ? location.name : L("Folder Home", "Home folder"), systemImage: location.symbol)
                            .tag(location)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help(L("Pilih folder Home atau disk lain", "Choose the Home folder or another disk"))
            }
        }
        // A disk that was ejected can't be scanned anymore.
        .onChange(of: volumes.volumes) {
            if !volumes.contains(selection) { selection = .home }
        }
    }
}
