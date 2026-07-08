import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Any existing visit means this isn't a first run — skip onboarding for upgrading users.
    @Query private var visits: [Visit]

    var body: some View {
        if hasCompletedOnboarding || !visits.isEmpty {
            // Single-surface app for now: just the Journal (Ask is a sheet from its toolbar).
            // People is temporarily hidden — restore the TabView to bring it back.
            JournalListView()
        } else {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }
}
