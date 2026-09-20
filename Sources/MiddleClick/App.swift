import ApplicationServices
import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mapper = MouseEventMapper()
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var stateItem: NSMenuItem?
    private var maintenanceTimer: Timer?
    private var gestureConflict: SystemSettings.GestureConflict?
    private var lastEnableError: MapperError?

    private var desiredEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "enabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        updateGesturePolicy()
        if desiredEnabled {
            enable(promptForPermission: true)
        } else {
            updateMenu()
        }

        maintenanceTimer = Timer.scheduledTimer(
            withTimeInterval: 10,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.performMaintenance()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        maintenanceTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        mapper.stop()
    }

    private func setupMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .systemFont(ofSize: 14, weight: .semibold)
        statusItem.button?.toolTip = "MiddleClick"

        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: "",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MiddleClick",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.toggleItem = toggleItem
        self.stateItem = stateItem
        updateMenu()
    }

    private func enable(promptForPermission: Bool) {
        guard desiredEnabled else { return }
        if promptForPermission && !AXIsProcessTrusted() {
            // kAXTrustedCheckOptionPrompt is imported as mutable global state in
            // Swift 6; its documented CFString value is safe to use directly.
            let options = ["AXTrustedCheckOptionPrompt": true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }

        do {
            try mapper.start()
            lastEnableError = nil
        } catch let error as MapperError {
            lastEnableError = error
        } catch {
            lastEnableError = .eventTapCreationFailed
        }
        updateMenu()
    }

    private func performMaintenance() {
        updateGesturePolicy()
        if desiredEnabled {
            if mapper.isEnabled {
                mapper.refreshDevices()
            } else if AXIsProcessTrusted() {
                enable(promptForPermission: false)
            }
        }
        updateMenu()
    }

    private func updateGesturePolicy() {
        gestureConflict = SystemSettings.gestureConflict
        mapper.gestureMappingAllowed = gestureConflict == nil
    }

    private func updateMenu() {
        toggleItem?.title = desiredEnabled ? "Disable MiddleClick" : "Enable MiddleClick"
        if mapper.isEnabled {
            if let gestureConflict {
                statusItem?.button?.title = "⊘⊘⊘"
                switch gestureConflict {
                case .threeFingerDrag:
                    stateItem?.title = "Paused — Three Finger Drag is on"
                case .threeFingerLookUp:
                    stateItem?.title = "Paused — three-finger Look Up is on"
                }
            } else {
                statusItem?.button?.title = "•••"
                stateItem?.title = "Active — taps, clicks, and drags"
            }
        } else if desiredEnabled {
            statusItem?.button?.title = "⊘⊘⊘"
            switch lastEnableError {
            case .eventTapCreationFailed:
                stateItem?.title = "Could not create event tap — retrying"
            case .accessibilityPermissionMissing, nil:
                stateItem?.title = "Waiting for Accessibility permission"
            }
        } else {
            statusItem?.button?.title = "⊘⊘⊘"
            stateItem?.title = "Disabled"
        }
    }

    @objc private func toggleEnabled() {
        desiredEnabled.toggle()
        if desiredEnabled {
            enable(promptForPermission: true)
        } else {
            mapper.stop()
            lastEnableError = nil
            updateMenu()
        }
    }

    @objc private func didWake() {
        guard desiredEnabled else { return }
        mapper.stop()
        enable(promptForPermission: false)
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct MiddleClickApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
