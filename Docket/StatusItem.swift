import AppKit
import SwiftUI

/// kip's menu-bar item. It is an AppKit status item, not SwiftUI's MenuBarExtra, because only
/// NSStatusItem takes an autosaveName. Without one macOS keeps no position for kip and puts it at the
/// far left on every launch, which on a full bar is inside the hidden part.
@MainActor
final class StatusItemController: NSObject {
    nonisolated static let autosaveName = "kip"
    /// Points from the right edge of the screen: just left of the system items, where kip stays visible.
    nonisolated static let firstPosition = 230.0

    private let store: CompanionStore
    private let item: NSStatusItem
    private let popover = NSPopover()

    init(store: CompanionStore) {
        self.store = store
        Self.seedPosition(in: .standard)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = Self.autosaveName
        item.isVisible = true
        item.button?.target = self
        item.button?.action = #selector(toggle(_:))

        let host = NSHostingController(rootView: CompanionView().environment(store).onAppear { store.reload() })
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        render()
    }

    /// Gives kip a starting place on first launch only. Once macOS has saved a position, including one
    /// the user picked by ⌘-dragging, it is left alone.
    nonisolated static func seedPosition(in defaults: UserDefaults) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(firstPosition, forKey: key)
        defaults.set(true, forKey: "NSStatusItem Visible \(autosaveName)")
    }

    /// Draws the icon for the current mood and redraws whenever the store's data or clock changes.
    private func render() {
        withObservationTracking {
            let model = store.model
            item.button?.image = MenuIcon.image(model.mood, stale: model.isBriefStale)
            item.button?.setAccessibilityLabel(model.robotLabel)
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        NSApp.activate()  // so Ask and the task editor take typing
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
