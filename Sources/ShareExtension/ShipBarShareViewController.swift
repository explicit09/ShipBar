import UIKit
import UniformTypeIdentifiers

final class ShipBarShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            await self.saveSharedCapture()
        }
    }

    private func configureView() {
        self.view.backgroundColor = .systemBackground
        self.statusLabel.text = "Saving to ShipBar..."
        self.statusLabel.font = .preferredFont(forTextStyle: .headline)
        self.statusLabel.textAlignment = .center
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.statusLabel)

        NSLayoutConstraint.activate([
            self.statusLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),
            self.statusLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
        ])
    }

    private func saveSharedCapture() async {
        do {
            let payload = await self.capturePayload()
            try SharedCaptureStore.appendToSharedContainer(payload)
            self.statusLabel.text = "Saved to ShipBar Inbox"
            self.completeAfterDelay()
        } catch {
            self.statusLabel.text = "Could not save capture"
            self.extensionContext?.cancelRequest(withError: error)
        }
    }

    private func completeAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func capturePayload() async -> SharedCapturePayload {
        let providers = self.extensionContext?
            .inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        var capturedText = ""
        var capturedURL = ""

        for provider in providers {
            if capturedURL.isEmpty,
               provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = await self.loadURL(from: provider)
            {
                capturedURL = url.absoluteString
            }

            if capturedText.isEmpty,
               provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = await self.loadString(from: provider, typeIdentifier: UTType.plainText.identifier)
            {
                capturedText = text
            }
        }

        if capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            capturedText = capturedURL
        }

        return SharedCapturePayload(
            text: capturedText,
            sourceApp: "Share Sheet",
            sourceURL: capturedURL)
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let value = String(data: data, encoding: .utf8),
                          let url = URL(string: value)
                {
                    continuation.resume(returning: url)
                } else if let value = item as? String,
                          let url = URL(string: value)
                {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadString(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
