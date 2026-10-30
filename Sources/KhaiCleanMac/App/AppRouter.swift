import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, access, ready

    var id: Int { rawValue }
}

/// Lets places outside the main window (Settings, the sidebar, Home, the menu bar) ask it to show the
/// guide or a module.
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()

    var onboarding: OnboardingStep?
    /// A module the window should switch to; it clears this once it has.
    var requestedModule: Module?
    /// The access guide reopens at most once per launch, not every time the window does.
    var didOfferAccessGuide = false

    func showOnboarding(at step: OnboardingStep = .welcome) {
        AppWindow.show()
        onboarding = step
    }

    /// Opens the window (or brings it forward) at `module`.
    func show(_ module: Module) {
        requestedModule = module
        AppWindow.show()
    }
}
