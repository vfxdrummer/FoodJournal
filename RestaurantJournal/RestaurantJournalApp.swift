import SwiftUI
import SwiftData

@main
struct RestaurantJournalApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Restaurant.self,
            Visit.self,
            PhotoAsset.self,
            VoiceNote.self,
            ScreenedPhoto.self,
            EstablishmentLogo.self,
            Person.self,
            DetectedFace.self,
            FaceScannedPhoto.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .task { Analytics.log("app_open") }
        }
        .modelContainer(sharedModelContainer)
    }
}
