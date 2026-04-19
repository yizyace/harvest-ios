import SwiftUI

@main
struct HarvestApp: App {

    @State private var appModel = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .task { await appModel.validateSessionOnLaunch() }
                .onOpenURL { url in
                    Task { await appModel.handleIncomingURL(url) }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.isSignedIn {
            BookmarkListView()
        } else {
            SignInView()
        }
    }
}
