//
//  OnboardingView.swift
//  Nubrix
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

enum OnboardingStep {
    case welcome
    case calendarPermission
    case accessibilityPermission
    case notificationsFromApps
    case musicPermission
    case finished
}

private let calendarService = CalendarService.shared

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
                        step = .calendarPermission
                    }
                }
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "Nubrix can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                        Task {
                                await requestCalendarPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .accessibilityPermission
                                }
                        }
                    },
                    onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .accessibilityPermission
                            }
                    }
                )
                .transition(.opacity)

            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access is required to replace system notifications with the Nubrix HUD. This allows the app to intercept media and brightness events to display custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        Task {
                            await requestAccessibilityPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .notificationsFromApps
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .notificationsFromApps
                        }
                    }
                )
                .transition(.opacity)
                
            case .notificationsFromApps:
                PermissionRequestView(
                    icon: Image(systemName: "bell.badge"),
                    title: "Notifications in the Notch",
                    description: "Optionally see new notifications from WhatsApp, Slack, Mail and other apps in the notch. This needs Full Disk Access, which you give in System Settings. Nubrix shows you how.",
                    privacyNote: "Only the apps you choose are read. Nothing is stored or sent anywhere.",
                    allowTitle: "Set Up",
                    onAllow: {
                        FullDiskAccessGuide.begin()
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
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
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    func requestCalendarPermission() async {
        _ = try? await calendarService.requestAccess(to: .event)
    }

    func requestAccessibilityPermission() async {
        _ = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
    }
}
