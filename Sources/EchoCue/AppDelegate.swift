import AppKit
import ApplicationServices
import Combine
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = AppState.shared
    private var overlayPanel: FloatingPanel!
    private var editorWindow: NSWindow!
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var didRequestKeyboardPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createOverlay()
        createEditor()
        createStatusItem()
        observeState()
        installKeyboardMonitors()
        positionOverlayBelowCamera()
        overlayPanel.orderFrontRegardless()
        editorWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    private func createOverlay() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 230),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 540, height: 190)
        panel.maxSize = NSSize(width: 1300, height: 360)
        panel.contentView = NSHostingView(rootView: TeleprompterView(state: state))
        panel.sharingType = state.captureProtectionEnabled ? .none : .readOnly
        overlayPanel = panel
    }

    private func createEditor() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EchoCue Script"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScriptEditorView(state: state))
        editorWindow = window
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "EchoCue")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Edit Script…", action: #selector(showEditor), keyEquivalent: "e").target = self
        menu.addItem(withTitle: overlayPanel.isVisible ? "Hide Overlay" : "Show Overlay",
                     action: #selector(toggleOverlay), keyEquivalent: "o").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: state.isListening ? "Pause Listening" : "Start Listening",
                     action: #selector(toggleListening), keyEquivalent: "l").target = self
        menu.addItem(withTitle: "Previous Cue", action: #selector(previousCue), keyEquivalent: "[").target = self
        menu.addItem(withTitle: "Next Cue", action: #selector(nextCue), keyEquivalent: "]").target = self
        menu.addItem(withTitle: "Restart Script", action: #selector(restartScript), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Move Below Camera", action: #selector(moveBelowCamera), keyEquivalent: "0").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit EchoCue", action: #selector(quit), keyEquivalent: "q").target = self
    }

    private func observeState() {
        state.$captureProtectionEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.overlayPanel?.sharingType = enabled ? .none : .readOnly
            }
            .store(in: &cancellables)

        state.$isListening
            .removeDuplicates()
            .sink { [weak self] listening in
                guard let self, listening, self.state.rightArrowAdvanceEnabled,
                      !self.didRequestKeyboardPermission else { return }
                self.didRequestKeyboardPermission = true
                if !CGPreflightListenEventAccess() {
                    _ = CGRequestListenEventAccess()
                }
            }
            .store(in: &cancellables)
    }

    private func installKeyboardMonitors() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleRightArrow(event)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Never steal arrow navigation while the script editor is active.
            guard !self.editorWindow.isKeyWindow else { return event }
            return self.handleRightArrow(event) ? nil : event
        }
    }

    @discardableResult
    private func handleRightArrow(_ event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.keyCode == 124,
              event.modifierFlags.intersection(disallowedModifiers).isEmpty,
              state.isListening,
              state.rightArrowAdvanceEnabled,
              overlayPanel.isVisible else { return false }
        state.advanceByKeyboard()
        return true
    }

    @objc private func showEditor() {
        editorWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleOverlay() {
        overlayPanel.isVisible ? overlayPanel.orderOut(nil) : overlayPanel.orderFrontRegardless()
    }

    @objc private func toggleListening() { state.toggleListening() }
    @objc private func previousCue() { state.goBack() }
    @objc private func nextCue() { state.advance() }
    @objc private func restartScript() { state.restart() }
    @objc private func moveBelowCamera() { positionOverlayBelowCamera() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func positionOverlayBelowCamera() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = overlayPanel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 10
        )
        overlayPanel.setFrameOrigin(origin)
    }
}
