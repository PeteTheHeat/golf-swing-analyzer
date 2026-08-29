import SwiftData
import SwiftUI
@main
struct SwingLabApp: App {
    private let modelContainer: ModelContainer?

    init() {
        modelContainer = SwingPersistence.makeLaunchContainer()
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                RootTabView()
                    .modelContainer(modelContainer)
                    .preferredColorScheme(.dark)
            } else {
                ContentUnavailableView(
                    "SwingLab Can't Start",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Storage is unavailable. Restart the app or free device storage, then try again.")
                )
                .preferredColorScheme(.dark)
            }
        }
    }
}
