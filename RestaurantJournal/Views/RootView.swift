import SwiftUI

struct RootView: View {
    var body: some View {
        // Single-surface app for now: just the Journal (Ask is a sheet from its toolbar).
        // People is temporarily hidden — restore the TabView to bring it back.
        JournalListView()
    }
}
