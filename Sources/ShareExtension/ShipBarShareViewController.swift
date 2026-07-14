import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShipBarShareViewController: UIViewController {
    private var didPresentPreview = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        Task {
            await self.presentPreview()
        }
    }

    @MainActor
    private func presentPreview() async {
        guard !self.didPresentPreview else { return }
        self.didPresentPreview = true

        let payload = await self.capturePayload()
        let preview = ShipBarSharePreviewView(
            payload: payload,
            complete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            })

        let hosting = UIHostingController(rootView: preview)
        self.addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
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
