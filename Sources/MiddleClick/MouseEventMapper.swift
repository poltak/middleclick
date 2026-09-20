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
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var activeSourceButton: SourceButton?
    private var emittedTapCount: UInt64 = 0
    private var remappedPhysicalClickCount: UInt64 = 0
    private(set) var isEnabled = false
    var tapMappingAllowed = true
    var physicalClickMappingAllowed = true

    func start() throws {
        guard !isEnabled else { return }
        guard AXIsProcessTrusted() else {
            throw MapperError.accessibilityPermissionMissing
        }

        let eventTypes: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
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

        TouchInputController.shared.start { [weak self] in
            self?.emitTap()
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

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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

        if activeSourceButton == nil,
           physicalClickMappingAllowed,
           let sourceButton = sourceButton(forDownEvent: type),
           TouchInputController.shared.claimMouseClick()
        {
            activeSourceButton = sourceButton
            remappedPhysicalClickCount &+= 1
            postMiddleEvent(type: .otherMouseDown, copying: event)
            return nil
        }

        guard let activeSourceButton else {
            return Unmanaged.passUnretained(event)
        }

        if isDrag(type, for: activeSourceButton) {
            postMiddleEvent(type: .otherMouseDragged, copying: event)
            return nil
        }

        if isUp(type, for: activeSourceButton) {
            postMiddleEvent(type: .otherMouseUp, copying: event)
            self.activeSourceButton = nil
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func emitTap() {
        guard isEnabled, tapMappingAllowed, activeSourceButton == nil else { return }
        emittedTapCount &+= 1
        let location = CGEvent(source: nil)?.location ?? NSEvent.mouseLocation
        postMiddleEvent(type: .otherMouseDown, at: location, flags: [])
        postMiddleEvent(type: .otherMouseUp, at: location, flags: [])
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
