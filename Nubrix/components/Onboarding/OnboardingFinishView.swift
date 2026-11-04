//
//  OnboardingFinishView.swift
//  Nubrix
//
//  Created by Alexander on 2025-06-23.
//


import SwiftUI

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 54))
                .foregroundColor(.effectiveAccent)
                .padding()

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Move the pointer to the top middle of your screen, onto the notch, to open Nubrix.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("Music, notifications and device batteries show up there on their own.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            Spacer()

            VStack(spacing: 12) {
                Button(action: onOpenSettings) {
                    Label("Open Settings", systemImage: "gear")
                        .controlSize(.large)
                }
                .controlSize(.large)

                Button("Finish", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    OnboardingFinishView(onFinish: { }, onOpenSettings: { })
}
