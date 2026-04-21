import SwiftUI

struct SettingsView: View {

    @Environment(AppModel.self) private var appModel

    @State private var showPrivacySheet = false
    @State private var showFirstDeleteConfirm = false
    @State private var showSecondDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    showPrivacySheet = true
                } label: {
                    HStack {
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                Button(role: .destructive) {
                    showFirstDeleteConfirm = true
                } label: {
                    if deleting {
                        HStack {
                            Text("Deleting…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Delete Account")
                    }
                }
                .disabled(deleting)
            } footer: {
                Text("Deleting your account permanently removes your bookmarks, tags, and session data. This can't be undone.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPrivacySheet) {
            SafariWebView(url: Self.privacyURL)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Delete Harvest account?",
            isPresented: $showFirstDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                showSecondDeleteConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Are you sure?",
            isPresented: $showSecondDeleteConfirm
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your bookmarks, tags, and account. This can't be undone.")
        }
        .alert(
            "Couldn't delete account",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            ),
            presenting: deleteErrorMessage
        ) { _ in
            Button("Retry") {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    /// Per-environment privacy policy URL. Derived from the configured base
    /// URL so dev and prod both point at their own `/privacy` page.
    static var privacyURL: URL {
        AppEnvironment.current.baseURL.appendingPathComponent("privacy")
    }

    private func performDelete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await appModel.deleteAccount()
            // Session cleared inside AppModel.deleteAccount; RootView
            // observes isSignedIn and pops to SignInView automatically.
        } catch {
            deleteErrorMessage = (error as? APIError)?.userFacingMessage ?? "Couldn't delete account."
        }
    }
}
