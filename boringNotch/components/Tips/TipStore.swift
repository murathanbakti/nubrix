//
//  TipStore.swift
//  boringNotch
//
//  Created by Richard Kunkli on 15/09/2024.
//

import SwiftUI
import TipKit

struct VitrinTip: Tip {
    var title: Text {
        Text("Your clipboard, on display")
    }

    var message: Text? {
        Text("Press ⌃⌥V to open the Vitrin showcase and search everything you copied.")
    }

    var image: Image? {
        Image(systemName: "square.on.square")
    }
}

struct ClaudeTip: Tip {
    var title: Text {
        Text("Claude Code in the notch")
    }

    var message: Text? {
        Text("Install the Nubrix hooks and watch your Claude Code sessions from the Claude tab.")
    }

    var image: Image? {
        Image(systemName: "sparkle")
    }
}

struct NotchctlTip: Tip {
    var title: Text {
        Text("Notify from your terminal")
    }

    var message: Text? {
        Text("Run notchctl notify \"Build done\" to show a banner in the notch and a line in the Dev tab.")
    }

    var image: Image? {
        Image(systemName: "terminal")
    }
}

struct TipsView: View {
    var vitrinTip = VitrinTip()
    var claudeTip = ClaudeTip()
    var notchctlTip = NotchctlTip()
    var body: some View {
        VStack {
            TipView(vitrinTip)
            TipView(claudeTip)
            TipView(notchctlTip)
        }
        .task {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
    }
}

#Preview {
    TipsView()
}
