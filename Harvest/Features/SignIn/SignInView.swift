import SwiftUI

struct SignInView: View {

    @Environment(AppModel.self) private var appModel
    @State private var email: String = ""
    @State private var pastedToken: String = ""
    @State private var sendingLink = false
    @State private var verifyingToken = false
    @State private var sentMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit(send)

                    Button(action: send) {
                        if sendingLink {
                            ProgressView()
                        } else {
                            Text("Send magic link")
                        }
                    }
                    .disabled(email.isEmpty || sendingLink)
                } header: {
                    Text("Sign in to Harvest")
                } footer: {
                    if let sentMessage {
                        Text(sentMessage).foregroundStyle(.secondary)
                    } else {
                        Text("We'll email you a link that signs you in.").foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Paste token", text: $pastedToken, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...4)
                    Button(action: submitToken) {
                        if verifyingToken { ProgressView() } else { Text("Sign in with token") }
                    }
                    .disabled(pastedToken.isEmpty || verifyingToken)
                } header: {
                    Text("Or paste a token")
                } footer: {
                    // handoff §4: Universal Links require an AASA file on
                    // the monolith that hasn't shipped yet. Until it does,
                    // users open the verify link in Safari, copy the token
                    // shown on the HTML page, and paste it here.
                    Text(
                        "Open the magic-link email on another device, tap the link in Safari, "
                        + "copy the token shown there, and paste it above."
                    )
                    .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Harvest")
        }
    }

    private func send() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        sendingLink = true
        errorMessage = nil
        Task {
            defer { sendingLink = false }
            do {
                try await appModel.sendMagicLink(email: address)
                sentMessage = "Magic link sent to \(address). Check your inbox."
            } catch {
                errorMessage = (error as? APIError)?.userFacingMessage ?? "Couldn't send link."
            }
        }
    }

    private func submitToken() {
        let token = pastedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        verifyingToken = true
        errorMessage = nil
        Task {
            defer { verifyingToken = false }
            do {
                try await appModel.completeSignIn(withToken: token)
                // SessionStore update triggers root view rebuild → dismiss.
            } catch {
                errorMessage = (error as? APIError)?.userFacingMessage ?? "Couldn't verify token."
            }
        }
    }
}
