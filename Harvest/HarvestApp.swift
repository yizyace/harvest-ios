import SwiftUI

@main
struct HarvestApp: App {

    @State private var appModel = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .task { await appModel.validateSessionOnLaunch() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.isSignedIn {
            SignedInPlaceholder()
        } else {
            SignInView()
        }
    }
}

// Replaced in commit 7 with the real BookmarkListView.
private struct SignedInPlaceholder: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Signed in as \(appModel.sessionStore.user?.email ?? "—")")
                Button("Sign out") {
                    Task { await appModel.signOut() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Harvest")
        }
    }
}
