import AppKit
import SwiftData
import SwiftUI

@main
struct ShipBarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("ShipBar")
                .padding()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private lazy var modelContainer: ModelContainer = {
        do {
            return try ShipBarModelContainer.make()
        } catch {
            print("Unable to create CloudKit-backed ShipBar model container: \(error)")
            return try! ShipBarModelContainer.make(inMemory: true)
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)
        self.configurePopover()
        self.configureStatusItem()
    }

    private func configurePopover() {
        let root = ShipBarRootView()
            .modelContainer(self.modelContainer)
            .frame(width: ShipBarStyle.panelWidth, height: ShipBarStyle.panelHeight)
            .background(Color.clear)
        self.popover.behavior = .transient
        self.popover.contentSize = NSSize(width: ShipBarStyle.panelWidth, height: ShipBarStyle.panelHeight)
        self.popover.contentViewController = VisualEffectHostingController(rootView: root)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "ShipBar")
        item.button?.image?.isTemplate = true
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        self.statusItem = item
    }

    @objc private func togglePopover() {
        guard let button = self.statusItem?.button else { return }
        if self.popover.isShown {
            self.popover.performClose(nil)
        } else {
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private final class VisualEffectHostingController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>

    init(rootView: Content) {
        self.hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        self.view = effectView

        self.addChild(self.hostingController)
        let hostedView = self.hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
    }
}
