//
//  TabButton.swift
//  Nubrix
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    var badge: Color? = nil
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .padding(.horizontal, 8)
                .contentShape(Capsule())
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Circle()
                            .fill(badge)
                            .frame(width: 6, height: 6)
                            .background(Circle().fill(.black).padding(-1))
                            .offset(x: -1, y: 1)
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
