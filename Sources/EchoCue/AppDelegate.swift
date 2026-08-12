import AppKit
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
    private var globalHotKeyController: GlobalHotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createOverlay()
        createEditor()
        createStatusItem()
        createGlobalHotKey()
        observeState()
        positionOverlayBelowCamera()
        overlayPanel.orderFrontRegardless()
        editorWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
        let globalTitle = state.globalHotKeyEnabled
            ? "Global Next Cue: \(state.globalAdvanceKey.symbol)"
            : "Global Next Cue: Off"
        menu.addItem(withTitle: globalTitle, action: nil, keyEquivalent: "").isEnabled = false
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

        Publishers.CombineLatest(
            state.$globalHotKeyEnabled.removeDuplicates(),
            state.$globalAdvanceKey.removeDuplicates()
        )
            .sink { [weak self] enabled, key in
                self?.configureGlobalHotKey(enabled: enabled, key: key)
            }
            .store(in: &cancellables)
    }

    private func createGlobalHotKey() {
        globalHotKeyController = GlobalHotKeyController { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.state.advanceByGlobalHotKey()
                if !self.overlayPanel.isVisible {
                    self.overlayPanel.orderFrontRegardless()
                }
            }
        }
    }

    private func configureGlobalHotKey(enabled: Bool, key: GlobalAdvanceKey) {
        guard enabled else {
            globalHotKeyController?.unregister()
            state.setGlobalHotKeyStatus("Global shortcut is off")
            return
        }

        let status = globalHotKeyController?.register(key) ?? OSStatus(paramErr)
        if status == noErr {
            state.setGlobalHotKeyStatus("\(key.symbol) works globally—even when listening stops")
        } else {
            state.setGlobalHotKeyStatus("Could not register \(key.displayName); choose another key")
        }
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
