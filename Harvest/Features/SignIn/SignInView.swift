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
                    Text(AppEnvironment.current.supportsUniversalLinks ? "Or paste a token" : "Paste verify token")
                } footer: {
                    Text(pasteFooterCopy).foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Harvest")
        }
    }

    private var pasteFooterCopy: String {
        if AppEnvironment.current.supportsUniversalLinks {
            // Universal Links path: AASA file on harvest.bitrat.io isn't
            // shipped yet, so the fallback is opening the link in another
            // Safari (phone, iPad, or desktop), copying the token from the
            // HTML verify page, and pasting here.
            return "Open the magic-link email in Safari, copy the token shown on the page, and paste it above."
        } else {
            // Dev path: harvest.bitrat.test is not publicly resolvable, so
            // iOS can never resolve the verify link — the desktop-browser
            // flow is the only way to land a session token here.
            return "Open the email on your desktop, open the verify link in a browser on the machine running harvest.bitrat.test, then copy the token shown on the page and paste it above."
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
