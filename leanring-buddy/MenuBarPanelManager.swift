//
//  MenuBarPanelManager.swift
//  leanring-buddy
//
//  Manages the NSStatusItem (menu bar icon) and a custom borderless NSPanel
//  that drops down below it when clicked. The panel hosts a SwiftUI view
//  (CompanionPanelView) via NSHostingView. Uses the same NSPanel pattern as
//  FloatingSessionButton and GlobalPushToTalkOverlay for consistency.
//
//  The panel is non-activating so it does not steal focus from the user's
//  current app, and auto-dismisses when the user clicks outside.
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let clickyDismissPanel = Notification.Name("clickyDismissPanel")
}

/// Custom NSPanel subclass that can become the key window even with
/// .nonactivatingPanel style, allowing text fields to receive focus.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class MenuBarPanelManager: NSObject {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickOutsideMonitor: Any?
    private var dismissPanelObserver: NSObjectProtocol?
    private var panelToggleKeyMonitor: Any?

    private let companionManager: CompanionManager
    private let panelWidth: CGFloat = 320
    private let panelHeight: CGFloat = 380

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        super.init()
        createStatusItem()
        installPanelToggleKeyboardShortcut()

        dismissPanelObserver = NotificationCenter.default.addObserver(
            forName: .clickyDismissPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    deinit {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = dismissPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = panelToggleKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Status Item

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else {
            print("⚠️ Clicky menu bar: failed to get status item button")
            return
        }

        // Use an SF Symbol for reliable rendering across all macOS versions.
        // The custom-drawn triangle was invisible on some systems.
        if let sfImage = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "Clicky") {
            sfImage.isTemplate = true
            button.image = sfImage
        } else {
            // Fallback: use the text "C" if the SF Symbol isn't available
            button.title = "C"
        }

        button.action = #selector(statusItemClicked)
        button.target = self
        print("🎯 Clicky menu bar: status item created successfully")
    }

    /// Opens the panel automatically on app launch so the user sees
    /// permissions and the start button right away.
    func showPanelOnLaunch() {
        // Small delay so the status item has time to appear in the menu bar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showPanel()
        }
    }

    /// Cmd+Shift+C toggles the panel from anywhere, so the user can access
    /// settings even if the menu bar icon is hidden behind the notch.
    private func installPanelToggleKeyboardShortcut() {
        panelToggleKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd+Shift+C — keyCode 8 is "C"
            let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
            let relevantFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 8 && relevantFlags == requiredFlags {
                DispatchQueue.main.async {
                    self?.togglePanel()
                }
            }
        }
        print("🎯 Clicky: Cmd+Shift+C keyboard shortcut installed for panel toggle")
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    @objc private func statusItemClicked() {
        togglePanel()
    }

    // MARK: - Panel Lifecycle

    private func showPanel() {
        if panel == nil {
            createPanel()
        }

        positionPanelBelowStatusItem()

        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
        installClickOutsideMonitor()
    }

    private func hidePanel() {
        // Save the panel's current position so it reopens where the user left it
        if let panelFrame = panel?.frame {
            UserDefaults.standard.set(panelFrame.origin.x, forKey: "clickyPanelPositionX")
            UserDefaults.standard.set(panelFrame.origin.y, forKey: "clickyPanelPositionY")
        }
        panel?.orderOut(nil)
        removeClickOutsideMonitor()
    }

    private func createPanel() {
        let companionPanelView = CompanionPanelView(companionManager: companionManager)
            .frame(width: panelWidth)

        let hostingView = NSHostingView(rootView: companionPanelView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let menuBarPanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        menuBarPanel.isFloatingPanel = true
        menuBarPanel.level = .floating
        menuBarPanel.isOpaque = false
        menuBarPanel.backgroundColor = .clear
        menuBarPanel.hasShadow = false
        menuBarPanel.hidesOnDeactivate = false
        menuBarPanel.isExcludedFromWindowsMenu = true
        menuBarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        menuBarPanel.isMovableByWindowBackground = true
        menuBarPanel.titleVisibility = .hidden
        menuBarPanel.titlebarAppearsTransparent = true

        menuBarPanel.contentView = hostingView
        panel = menuBarPanel
    }

    private func positionPanelBelowStatusItem() {
        guard let panel else { return }

        let fittingSize = panel.contentView?.fittingSize ?? CGSize(width: panelWidth, height: panelHeight)
        let actualPanelHeight = fittingSize.height

        // If the user has previously dragged the panel, reopen at that saved position
        let hasSavedPosition = UserDefaults.standard.object(forKey: "clickyPanelPositionX") != nil
        if hasSavedPosition {
            let savedX = UserDefaults.standard.double(forKey: "clickyPanelPositionX")
            let savedY = UserDefaults.standard.double(forKey: "clickyPanelPositionY")
            panel.setFrame(
                NSRect(x: savedX, y: savedY, width: panelWidth, height: actualPanelHeight),
                display: true
            )
            return
        }

        // Try to position below the menu bar status item icon
        if let buttonWindow = statusItem?.button?.window {
            let statusItemFrame = buttonWindow.frame
            let gapBelowMenuBar: CGFloat = 4
            let panelOriginX = statusItemFrame.midX - (panelWidth / 2)
            let panelOriginY = statusItemFrame.minY - actualPanelHeight - gapBelowMenuBar
            panel.setFrame(
                NSRect(x: panelOriginX, y: panelOriginY, width: panelWidth, height: actualPanelHeight),
                display: true
            )
            return
        }

        // Fallback: position near the top-right of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelOriginX = screenFrame.maxX - panelWidth - 16
            let panelOriginY = screenFrame.maxY - actualPanelHeight - 16
            panel.setFrame(
                NSRect(x: panelOriginX, y: panelOriginY, width: panelWidth, height: actualPanelHeight),
                display: true
            )
        }
    }

    // MARK: - Click Outside Dismissal

    /// Installs a global event monitor that hides the panel when the user clicks
    /// anywhere outside it — the same transient dismissal behavior as NSPopover.
    /// Uses a short delay so that system permission dialogs (triggered by Grant
    /// buttons in the panel) don't immediately dismiss the panel when they appear.
    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return }

            // Check if the click is inside the status item button — if so, the
            // statusItemClicked handler will toggle the panel, so don't also hide.
            let clickLocation = NSEvent.mouseLocation
            if panel.frame.contains(clickLocation) {
                return
            }

            // Delay dismissal slightly to avoid closing the panel when
            // a system permission dialog appears (e.g. microphone access).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard panel.isVisible else { return }

                // If permissions aren't all granted yet, a system dialog
                // may have focus — don't dismiss during onboarding.
                if !self.companionManager.allPermissionsGranted && !NSApp.isActive {
                    return
                }

                self.hidePanel()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
