import ApplicationServices
import Cocoa
import CoreGraphics

enum MapperError: Error {
    case accessibilityPermissionMissing
    case eventTapCreationFailed
}

struct MouseMapperDiagnostics: Sendable {
    let touchInput: TouchInputDiagnostics
    let emittedTapCount: UInt64
    let remappedPhysicalClickCount: UInt64
}

final class MouseEventMapper: @unchecked Sendable {
    private enum SourceButton {
        case left
        case right

        var label: String {
            switch self {
            case .left: "left"
            case .right: "right"
            }
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var activeSourceButton: SourceButton?
    private var emittedTapCount: UInt64 = 0
    private var remappedPhysicalClickCount: UInt64 = 0
    private(set) var isEnabled = false
    var tapMappingAllowed = true {
        didSet { if oldValue != tapMappingAllowed { recordTraceSettings() } }
    }
    var physicalClickMappingAllowed = true {
        didSet { if oldValue != physicalClickMappingAllowed { recordTraceSettings() } }
    }

    func start() throws {
        guard !isEnabled else { return }
        guard AXIsProcessTrusted() else {
            throw MapperError.accessibilityPermissionMissing
        }

        let eventTypes: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .scrollWheel,
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let mapper = Unmanaged<MouseEventMapper>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                return mapper.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MapperError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        let currentRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)

        self.eventTap = eventTap
        runLoopSource = source
        runLoop = currentRunLoop
        activeSourceButton = nil
        isEnabled = true
        CGEvent.tapEnable(tap: eventTap, enable: true)
        recordTraceSettings()

        TouchInputController.shared.start { [weak self] tapID in
            self?.emitTap(tapID: tapID)
        }
    }

    func stop() {
        TouchInputController.shared.stop()
        releaseMiddleButtonIfNeeded()

        if let runLoop, let runLoopSource {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        runLoop = nil
        isEnabled = false
        recordTraceSettings()
    }

    func refreshDevices() {
        guard isEnabled else { return }
        TouchInputController.shared.refreshDevices()
    }

    func diagnostics() -> MouseMapperDiagnostics {
        MouseMapperDiagnostics(
            touchInput: TouchInputController.shared.diagnostics(),
            emittedTapCount: emittedTapCount,
            remappedPhysicalClickCount: remappedPhysicalClickCount
        )
    }

    func recordTraceSettings() {
        GestureTraceRecorder.shared.recordSettings(
            at: ProcessInfo.processInfo.systemUptime,
            mapperEnabled: isEnabled,
            tapMappingAllowed: tapMappingAllowed,
            physicalClickMappingAllowed: physicalClickMappingAllowed
        )
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .scrollWheel {
            GestureTraceRecorder.shared.recordScroll(
                at: ProcessInfo.processInfo.systemUptime,
                deltaX: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                deltaY: event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            )
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout {
            releaseMiddleButtonIfNeeded()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByUserInput {
            releaseMiddleButtonIfNeeded()
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
            return Unmanaged.passUnretained(event)
        }

        if activeSourceButton == nil, let sourceButton = sourceButton(forDownEvent: type) {
            let mappingAllowed = physicalClickMappingAllowed
            let claim = mappingAllowed ? TouchInputController.shared.claimMouseClick() : nil
            GestureTraceRecorder.shared.recordMouseButton(
                at: ProcessInfo.processInfo.systemUptime,
                stage: "down",
                button: sourceButton.label,
                mappingAllowed: mappingAllowed,
                claimed: claim != nil,
                tapID: claim?.tapID,
                source: claim?.source,
                suppressed: claim != nil
            )
            if claim != nil {
                activeSourceButton = sourceButton
                remappedPhysicalClickCount &+= 1
                postMiddleEvent(type: .otherMouseDown, copying: event)
                return nil
            }
        }

        guard let activeSourceButton else {
            return Unmanaged.passUnretained(event)
        }

        if isDrag(type, for: activeSourceButton) {
            GestureTraceRecorder.shared.recordMouseButton(
                at: ProcessInfo.processInfo.systemUptime,
                stage: "drag",
                button: activeSourceButton.label,
                mappingAllowed: physicalClickMappingAllowed,
                claimed: true,
                source: "middleClickFromPhysicalMouse",
                suppressed: true
            )
            postMiddleEvent(type: .otherMouseDragged, copying: event)
            return nil
        }

        if isUp(type, for: activeSourceButton) {
            GestureTraceRecorder.shared.recordMouseButton(
                at: ProcessInfo.processInfo.systemUptime,
                stage: "up",
                button: activeSourceButton.label,
                mappingAllowed: physicalClickMappingAllowed,
                claimed: true,
                source: "middleClickFromPhysicalMouse",
                suppressed: true
            )
            postMiddleEvent(type: .otherMouseUp, copying: event)
            self.activeSourceButton = nil
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func emitTap(tapID: UInt64) {
        guard isEnabled else {
            GestureTraceRecorder.shared.recordTapOutput(
                at: ProcessInfo.processInfo.systemUptime,
                tapID: tapID,
                emitted: false,
                reason: "mapperDisabled"
            )
            return
        }
        guard tapMappingAllowed else {
            GestureTraceRecorder.shared.recordTapOutput(
                at: ProcessInfo.processInfo.systemUptime,
                tapID: tapID,
                emitted: false,
                reason: "tapMappingDisabled"
            )
            return
        }
        guard activeSourceButton == nil else {
            GestureTraceRecorder.shared.recordTapOutput(
                at: ProcessInfo.processInfo.systemUptime,
                tapID: tapID,
                emitted: false,
                reason: "physicalClickAlreadyActive"
            )
            return
        }
        emittedTapCount &+= 1
        GestureTraceRecorder.shared.recordTapOutput(
            at: ProcessInfo.processInfo.systemUptime,
            tapID: tapID,
            emitted: true
        )
        let pointerEvent = CGEvent(source: nil)
        let location = pointerEvent?.location ?? NSEvent.mouseLocation
        let flags = pointerEvent?.flags ?? []
        postMiddleEvent(type: .otherMouseDown, at: location, flags: flags)
        postMiddleEvent(type: .otherMouseUp, at: location, flags: flags)
    }

    private func releaseMiddleButtonIfNeeded() {
        guard activeSourceButton != nil else { return }
        activeSourceButton = nil
        let location = CGEvent(source: nil)?.location ?? .zero
        postMiddleEvent(type: .otherMouseUp, at: location, flags: [])
    }

    private func postMiddleEvent(type: CGEventType, copying original: CGEvent) {
        postMiddleEvent(type: type, at: original.location, flags: original.flags)
    }

    private func postMiddleEvent(
        type: CGEventType,
        at location: CGPoint,
        flags: CGEventFlags
    ) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        event.flags = flags
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }

    private func sourceButton(forDownEvent type: CGEventType) -> SourceButton? {
        switch type {
        case .leftMouseDown: .left
        case .rightMouseDown: .right
        default: nil
        }
    }

    private func isDrag(_ type: CGEventType, for button: SourceButton) -> Bool {
        switch button {
        case .left: type == .leftMouseDragged
        case .right: type == .rightMouseDragged
        }
    }

    private func isUp(_ type: CGEventType, for button: SourceButton) -> Bool {
        switch button {
        case .left: type == .leftMouseUp
        case .right: type == .rightMouseUp
        }
    }
}
