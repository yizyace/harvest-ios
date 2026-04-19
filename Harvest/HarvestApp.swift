import SwiftUI

@main
struct HarvestApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Harvest")
                .font(.largeTitle.weight(.semibold))
            Text("Scaffolded. Next commits wire the API client, sign-in, and list.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
