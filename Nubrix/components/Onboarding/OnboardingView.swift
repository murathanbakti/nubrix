//
//  OnboardingView.swift
//  Nubrix
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

enum OnboardingStep {
    case welcome
    case features
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
                        step = .features
                    }
                }
                .transition(.opacity)

            case .features:
                OnboardingFeaturesView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        NubrixCoordinator.shared.firstLaunch = false
                        step = .finished
                    }
                }
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }
}
