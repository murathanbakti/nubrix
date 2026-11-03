//
//  OnboardingView.swift
//  Nubrix
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

enum OnboardingStep {
    case welcome
    case permissionsInfo
    case musicPermission
    case finished
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .permissionsInfo
                    }
                }
                .transition(.opacity)

            case .permissionsInfo:
                PermissionsInfoView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .musicPermission
                    }
                }
                .transition(.opacity)

            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            NubrixCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .onAppear { LaunchFlow().musicSourceDidAppear() }
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }
}

private struct PermissionsInfoView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 32)

            Text("Permissions When You Need Them")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Nubrix asks for access only the first time you use a feature that needs it. You can say no and allow it later.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 14) {
                row(symbol: "calendar", name: "Calendar", detail: "When you open the calendar from the notch")
                row(symbol: "web.camera", name: "Camera", detail: "When you open Mirror")
                row(symbol: "hand.raised.fill", name: "Accessibility", detail: "When you turn on the custom volume and brightness HUDs")
                row(symbol: "bell.badge", name: "Full Disk Access", detail: "When you turn on notifications from other apps")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            Text("Everything stays on your Mac.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Continue") { onContinue() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private func row(symbol: String, name: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundColor(.effectiveAccent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
