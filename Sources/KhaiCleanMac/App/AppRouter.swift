import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, access, ready

    var id: Int { rawValue }
}

/// Lets places outside the main window (Settings, the sidebar, Home) ask it to show the guide.
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()

    var onboarding: OnboardingStep?

    func showOnboarding(at step: OnboardingStep = .welcome) {
        AppWindow.show()
        onboarding = step
    }
}
