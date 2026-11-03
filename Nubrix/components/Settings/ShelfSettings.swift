import Defaults
import SwiftUI

struct ShelfSettings: View {
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection
    @Default(.nubrixShelf) var nubrixShelf
    @StateObject private var quickShareService = QuickShareService.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .nubrixShelf) {
                    Text("Enable shelf")
                }
                .onChange(of: nubrixShelf) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
            } footer: {
                SettingsFooter("A tray in the notch where you can drop files, then drag them out or share them.")
            }

            Group {
                Section {
                    Defaults.Toggle(key: .openShelfByDefault) {
                        Text("Open shelf by default if items are present")
                    }
                    Defaults.Toggle(key: .expandedDragDetection) {
                        Text("Expanded drag detection area")
                    }
                    .onChange(of: expandedDragDetection) {
                        NotificationCenter.default.post(
                            name: Notification.Name.expandedDragDetectionChanged,
                            object: nil
                        )
                    }
                    Defaults.Toggle(key: .copyOnDrag) {
                        Text("Copy items on drag")
                    }
                    Defaults.Toggle(key: .autoRemoveShelfItems) {
                        Text("Remove from shelf after dragging")
                    }
                } header: {
                    Text("Behavior")
                }

                Section {
                    Picker("Quick share service", selection: $quickShareProvider) {
                        ForEach(quickShareService.availableProviders, id: \.id) { provider in
                            HStack {
                                Group {
                                    if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                        Image(nsImage: nsImg)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    } else {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                }
                                .frame(width: 16, height: 16)
                                Text(provider.id)
                            }
                            .tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Quick share")
                } footer: {
                    SettingsFooter("Click the shelf button to pick files to share, or drag files onto it to share right away.")
                }
            }
            .disabled(!nubrixShelf)
        }
        .settingsPage(.shelf)
        .task { await QuickShareService.shared.discoverAvailableProviders() }
    }
}
