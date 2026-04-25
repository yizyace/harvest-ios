import UIKit
import UniformTypeIdentifiers

// Action extension for saving URLs from Safari (and any app whose share
// sheet surfaces a web URL). The flow:
//   1. Read a URL from inputItems (activation rule guarantees at least one).
//      For Safari shares, also pull the post-render outerHTML supplied by
//      SharePreprocessor.js so the backend can skip its own scrape (paywalls
//      / bot detection don't see what the user saw).
//   2. Read the session token from the shared keychain group — if missing,
//      tell the user to sign in and bail.
//   3. POST /api/v1/bookmarks via ShareAPIClient. On 202 we're done; on 422
//      duplicate show a friendly "already saved"; other errors allow retry.
final class ShareViewController: UIViewController {

    // Hard cap on UTF-8 bytes of HTML we ship to the server. Above this we
    // drop the field and fall back to URL-only (server scrapes). Sized to
    // cover normal articles while staying well under share-extension memory
    // and Rails request-body limits.
    private static let maxHTMLBytes = 2 * 1024 * 1024

    private let persistence: SessionPersistence = KeychainSessionPersistence()
    private lazy var client = ShareAPIClient(persistence: persistence)

    private let card = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let primaryButton = UIButton(configuration: .borderedProminent())
    private let secondaryButton = UIButton(configuration: .plain())
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var incomingURL: URL?
    private var incomingExtracted: ExtractedContent?
    private var incomingHTML: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        layout()

        Task { await begin() }
    }

    // MARK: - State transitions

    private func begin() async {
        guard persistence.readToken() != nil else {
            show(
                title: "Sign in to Harvest",
                message: "Open the Harvest app and sign in before saving bookmarks.",
                primary: ("Close", { [weak self] in self?.finish(success: false) }),
                secondary: nil
            )
            return
        }

        let preprocessor = await readPreprocessorResults()
        let preprocessorURL = (preprocessor?["url"] as? String).flatMap(URL.init(string:))
        let resolvedURL: URL?
        if let preprocessorURL {
            resolvedURL = preprocessorURL
        } else {
            resolvedURL = await readSharedURL()
        }
        guard let url = resolvedURL else {
            show(
                title: "No URL to save",
                message: "We couldn't find a URL in the share payload.",
                primary: ("Close", { [weak self] in self?.finish(success: false) }),
                secondary: nil
            )
            return
        }
        self.incomingURL = url
        self.incomingExtracted = (preprocessor?["extracted"] as? [String: Any]).flatMap(boundedExtracted)
        self.incomingHTML = incomingExtracted == nil
            ? (preprocessor?["html"] as? String).flatMap(boundedHTML)
            : nil
        await save(url: url, extracted: incomingExtracted, html: incomingHTML)
    }

    private func save(url: URL, extracted: ExtractedContent?, html: String?) async {
        show(
            title: "Saving to Harvest…",
            message: url.absoluteString,
            primary: nil,
            secondary: nil,
            showSpinner: true
        )

        do {
            _ = try await client.createBookmark(url: url, extracted: extracted, html: html)
            show(
                title: "Saved to Harvest",
                message: url.absoluteString,
                primary: ("Done", { [weak self] in self?.finish(success: true) }),
                secondary: nil
            )
        } catch APIError.validation(let errors) where errors.contains(where: { $0.field == "page_id" }) {
            show(
                title: "Already in Harvest",
                message: "You've saved this URL before.",
                primary: ("Done", { [weak self] in self?.finish(success: true) }),
                secondary: nil
            )
        } catch APIError.unauthorized {
            show(
                title: "Session expired",
                message: "Open Harvest and sign in again.",
                primary: ("Close", { [weak self] in self?.finish(success: false) }),
                secondary: nil
            )
        } catch {
            let message = (error as? APIError)?.userFacingMessage ?? "Couldn't save this URL."
            show(
                title: "Save failed",
                message: message,
                primary: ("Retry", { [weak self] in
                    guard let self, let url = self.incomingURL else { return }
                    Task {
                        await self.save(
                            url: url,
                            extracted: self.incomingExtracted,
                            html: self.incomingHTML
                        )
                    }
                }),
                secondary: ("Cancel", { [weak self] in self?.finish(success: false) })
            )
        }
    }

    // MARK: - Reading the share input

    private func readPreprocessorResults() async -> [String: Any]? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        let typeID = UTType.propertyList.identifier
        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers where provider.hasItemConformingToTypeIdentifier(typeID) {
                let payload: NSDictionary? = await withCheckedContinuation { cont in
                    provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                        cont.resume(returning: item as? NSDictionary)
                    }
                }
                if let results = payload?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                    return results
                }
            }
        }
        return nil
    }

    private func boundedHTML(_ html: String) -> String? {
        guard !html.isEmpty, html.utf8.count <= Self.maxHTMLBytes else { return nil }
        return html
    }

    private func boundedExtracted(_ dict: [String: Any]) -> ExtractedContent? {
        guard let content = dict["content"] as? String,
              !content.isEmpty,
              content.utf8.count <= Self.maxHTMLBytes
        else { return nil }
        return ExtractedContent(
            title: (dict["title"] as? String) ?? "",
            content: content,
            author: dict["author"] as? String,
            description: dict["description"] as? String,
            published: dict["published"] as? String,
            image: dict["image"] as? String,
            domain: dict["domain"] as? String,
            site: dict["site"] as? String,
            language: dict["language"] as? String,
            wordCount: dict["wordCount"] as? Int
        )
    }

    private func readSharedURL() async -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                if let url = await loadURL(from: provider) { return url }
            }
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await withCheckedContinuation { cont in
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    cont.resume(returning: item as? URL)
                }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await withCheckedContinuation { cont in
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let string = item as? String, let url = URL(string: string) {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - UI scaffold

    private func layout() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        view.addSubview(card)

        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        spinner.hidesWhenStopped = true

        let buttonsStack = UIStackView(arrangedSubviews: [secondaryButton, primaryButton])
        buttonsStack.spacing = 12
        buttonsStack.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, spinner, buttonsStack])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .fill
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])
    }

    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?

    private func show(
        title: String,
        message: String,
        primary: (String, () -> Void)?,
        secondary: (String, () -> Void)?,
        showSpinner: Bool = false
    ) {
        titleLabel.text = title
        messageLabel.text = message

        if showSpinner { spinner.startAnimating() } else { spinner.stopAnimating() }

        primaryAction = primary?.1
        primaryButton.configuration?.title = primary?.0
        primaryButton.isHidden = primary == nil
        primaryButton.removeTarget(nil, action: nil, for: .allEvents)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        secondaryAction = secondary?.1
        secondaryButton.configuration?.title = secondary?.0
        secondaryButton.isHidden = secondary == nil
        secondaryButton.removeTarget(nil, action: nil, for: .allEvents)
        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
    }

    @objc private func primaryTapped() { primaryAction?() }
    @objc private func secondaryTapped() { secondaryAction?() }

    private func finish(success: Bool) {
        if success {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } else {
            let error = NSError(domain: "ShareExtension", code: -1)
            extensionContext?.cancelRequest(withError: error)
        }
    }
}
