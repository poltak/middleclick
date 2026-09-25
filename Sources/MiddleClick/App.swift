import ApplicationServices
import Cocoa
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let mapper = MouseEventMapper()
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var stateItem: NSMenuItem?
    private var inputDiagnosticsItem: NSMenuItem?
    private var outputDiagnosticsItem: NSMenuItem?
    private var recordingStateItem: NSMenuItem?
    private var startRecordingItem: NSMenuItem?
    private var stopAndSaveRecordingItem: NSMenuItem?
    private var maintenanceTimer: Timer?
    private var menuRefreshTimer: Timer?
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
        menuRefreshTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        mapper.stop()
    }

    private func setupMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .systemFont(ofSize: 14, weight: .semibold)
        statusItem.button?.toolTip = "MiddleClick"

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
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

        let inputDiagnosticsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        inputDiagnosticsItem.isEnabled = false
        menu.addItem(inputDiagnosticsItem)

        let outputDiagnosticsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        outputDiagnosticsItem.isEnabled = false
        menu.addItem(outputDiagnosticsItem)
        menu.addItem(.separator())

        let recordingStateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        recordingStateItem.isEnabled = false
        menu.addItem(recordingStateItem)

        let startRecordingItem = NSMenuItem(
            title: "Start Gesture Recording",
            action: #selector(startGestureRecording),
            keyEquivalent: ""
        )
        startRecordingItem.target = self
        menu.addItem(startRecordingItem)

        let stopAndSaveRecordingItem = NSMenuItem(
            title: "Stop and Save Recording…",
            action: #selector(stopAndSaveGestureRecording),
            keyEquivalent: ""
        )
        stopAndSaveRecordingItem.target = self
        menu.addItem(stopAndSaveRecordingItem)
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
        self.inputDiagnosticsItem = inputDiagnosticsItem
        self.outputDiagnosticsItem = outputDiagnosticsItem
        self.recordingStateItem = recordingStateItem
        self.startRecordingItem = startRecordingItem
        self.stopAndSaveRecordingItem = stopAndSaveRecordingItem
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
        switch gestureConflict {
        case .threeFingerDrag:
            mapper.tapMappingAllowed = false
            mapper.physicalClickMappingAllowed = false
        case .threeFingerLookUp:
            mapper.tapMappingAllowed = false
            mapper.physicalClickMappingAllowed = true
        case nil:
            mapper.tapMappingAllowed = true
            mapper.physicalClickMappingAllowed = true
        }
    }

    private func updateMenu() {
        let diagnostics = mapper.diagnostics()
        let touch = diagnostics.touchInput
        toggleItem?.title = desiredEnabled ? "Disable MiddleClick" : "Enable MiddleClick"
        if mapper.isEnabled {
            if let gestureConflict {
                statusItem?.button?.title = "⊘⊘⊘"
                switch gestureConflict {
                case .threeFingerDrag:
                    stateItem?.title = "Paused — Three Finger Drag is on"
                case .threeFingerLookUp:
                    stateItem?.title = "Active — clicks only (three-finger Look Up is on)"
                }
            } else if touch.deviceCount == 0 {
                statusItem?.button?.title = "⊘⊘⊘"
                stateItem?.title = "No multitouch device detected"
            } else if touch.startedDeviceCount < touch.deviceCount {
                statusItem?.button?.title = "⊘⊘⊘"
                stateItem?.title = "Could not start trackpad input"
            } else if touch.callbackFrameCount == 0 {
                statusItem?.button?.title = "•••"
                stateItem?.title = "Ready — waiting for touch input"
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

        let unmatchedSuffix = touch.unmatchedFrameCount == 0
            ? ""
            : " · \(touch.unmatchedFrameCount) unmatched"
        inputDiagnosticsItem?.title =
            "Devices: \(touch.startedDeviceCount)/\(touch.deviceCount) · " +
            "\(touch.callbackFrameCount) touches · \(touch.activeContactCount) fingers" +
            unmatchedSuffix
        outputDiagnosticsItem?.title =
            "Three fingers: \(touch.recognizedTapCount) taps · " +
            "\(diagnostics.remappedPhysicalClickCount) clicks"
        inputDiagnosticsItem?.isHidden = !desiredEnabled
        outputDiagnosticsItem?.isHidden = !desiredEnabled

        let recorder = GestureTraceRecorder.shared
        if recorder.isRecording {
            recordingStateItem?.title = "Gesture recording: Recording"
        } else if recorder.hasRecording {
            recordingStateItem?.title = "Gesture recording: Stopped — save pending"
        } else {
            recordingStateItem?.title = "Gesture recording: Off"
        }
        startRecordingItem?.isEnabled =
            mapper.isEnabled && !recorder.isRecording && !recorder.hasRecording
        stopAndSaveRecordingItem?.title = recorder.isRecording
            ? "Stop and Save Recording…"
            : "Save Recording…"
        stopAndSaveRecordingItem?.isEnabled = recorder.isRecording || recorder.hasRecording
    }

    @objc private func startGestureRecording() {
        let recorder = GestureTraceRecorder.shared
        guard mapper.isEnabled, !recorder.isRecording, !recorder.hasRecording else { return }
        recorder.start()
        mapper.recordTraceSettings()
        updateMenu()
    }

    @objc private func stopAndSaveGestureRecording() {
        let recorder = GestureTraceRecorder.shared
        if recorder.isRecording {
            recorder.stop()
        }
        guard recorder.hasRecording else {
            updateMenu()
            return
        }

        updateMenu()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "Save Gesture Recording"
        panel.nameFieldStringValue = "middleclick-gesture-trace.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            updateMenu()
            return
        }

        do {
            guard let data = try recorder.recordingData() else {
                throw GestureRecordingSaveError.noRecordingData
            }
            try data.write(to: url, options: .atomic)
            recorder.clear()
        } catch {
            showRecordingSaveError(error)
        }
        updateMenu()
    }

    private func showRecordingSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Could not save the gesture recording."
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
        menuRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMenu()
            }
        }
        menuRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }
}

private enum GestureRecordingSaveError: LocalizedError {
    case noRecordingData

    var errorDescription: String? {
        "There is no stopped gesture recording to save."
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
