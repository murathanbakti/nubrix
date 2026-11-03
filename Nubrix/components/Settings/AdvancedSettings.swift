import Defaults
import SwiftUI

struct AdvancedSettings: View {
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer

    @State private var selectedListVisualizer: CustomVisualizer?
    @State private var isPresented = false
    @State private var name = ""
    @State private var url = ""
    @State private var speed: CGFloat = 1.0

    private var parsedURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard let parsed = URL(string: trimmed), parsed.scheme != nil, parsed.host != nil else { return nil }
        return parsed
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Hide title bar")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Window behavior")
            }

            visualizersSection
        }
        .settingsPage(.advanced)
    }

    private var visualizersSection: some View {
        Section {
            List {
                ForEach(customVisualizers, id: \.self) { visualizer in
                    HStack {
                        LottieView(
                            url: visualizer.url, speed: visualizer.speed,
                            loopMode: .loop
                        )
                        .frame(width: 30, height: 30, alignment: .center)
                        Text(visualizer.name)
                        Spacer(minLength: 0)
                        if selectedVisualizer == visualizer {
                            Text("Selected")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 8)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 2)
                    .background(
                        selectedListVisualizer == visualizer ? Color.effectiveAccent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedListVisualizer == visualizer {
                            selectedListVisualizer = nil
                            return
                        }
                        selectedListVisualizer = visualizer
                    }
                }
            }
            .safeAreaPadding(
                EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
            )
            .frame(minHeight: 120)
            .actionBar {
                HStack(spacing: 5) {
                    Button {
                        name = ""
                        url = ""
                        speed = 1.0
                        isPresented.toggle()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    Divider()
                    Button {
                        if let visualizer = selectedListVisualizer,
                           let index = customVisualizers.firstIndex(of: visualizer) {
                            selectedListVisualizer = nil
                            customVisualizers.remove(at: index)
                            if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                selectedVisualizer = customVisualizers[0]
                            }
                        }
                    } label: {
                        Image(systemName: "minus")
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                }
            }
            .controlSize(.small)
            .buttonStyle(PlainButtonStyle())
            .overlay {
                if customVisualizers.isEmpty {
                    Text("No custom visualizers")
                        .foregroundStyle(Color(.secondaryLabelColor))
                        .padding(.bottom, 22)
                }
            }
            .sheet(isPresented: $isPresented) {
                addSheet
            }
        } header: {
            HStack(spacing: 0) {
                Text("Custom visualizers (Lottie)")
                if !customVisualizers.isEmpty {
                    Text(" – \(customVisualizers.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var addSheet: some View {
        VStack(alignment: .leading) {
            Text("Add new visualizer")
                .font(.largeTitle.bold())
                .padding(.vertical)
            TextField("Name", text: $name)
            TextField("Lottie JSON URL", text: $url)
            HStack {
                Text("Speed")
                Spacer(minLength: 80)
                Text("\(speed, specifier: "%.1f")s")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                Slider(value: $speed, in: 0...2, step: 0.1)
            }
            .padding(.vertical)
            HStack {
                Button {
                    isPresented.toggle()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button {
                    if let parsedURL {
                        let visualizer: CustomVisualizer = .init(
                            UUID: UUID(),
                            name: name,
                            url: parsedURL,
                            speed: speed
                        )
                        if !customVisualizers.contains(visualizer) {
                            customVisualizers.append(visualizer)
                        }
                    }
                    isPresented.toggle()
                } label: {
                    Text("Add")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(parsedURL == nil)
            }
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .controlSize(.extraLarge)
        .padding()
    }
}
