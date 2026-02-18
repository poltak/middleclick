import Cocoa
import CoreGraphics
import os.lock

typealias MTDeviceRef = OpaquePointer

// We only need finger count, not touch details.
typealias MTContactCallback = @convention(c) (
    MTDeviceRef?,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

@_silgen_name("MTDeviceCreateList")
private func MTDeviceCreateList() -> CFArray

@_silgen_name("MTRegisterContactFrameCallback")
private func MTRegisterContactFrameCallback(
    _ device: MTDeviceRef,
    _ callback: MTContactCallback
) -> Int32

@_silgen_name("MTDeviceStart")
private func MTDeviceStart(_ device: MTDeviceRef, _ unknown: Int32) -> Int32

final class FingerTracker: @unchecked Sendable {
    static let shared = FingerTracker()

    private var callback: MTContactCallback?
    private var lock = os_unfair_lock_s()
    private var _fingerCount: Int32 = 0
    private var _lastThreeFingerTimeNs: UInt64 = 0
    private var _lastCount: Int32 = 0
    private var _touchSequenceStartNs: UInt64 = 0
    private var _touchSequenceHadThree = false
    private var _lastPhysicalThreeFingerClickNs: UInt64 = 0
    private var _tapHandler: (() -> Void)?

    func start() {
        let cb: MTContactCallback = { _, _, count, _, _ in
            let now = DispatchTime.now().uptimeNanoseconds
            FingerTracker.shared.updateFingerState(count: count, nowNs: now)
            return 0
        }
        self.callback = cb

        let list = MTDeviceCreateList()
        let deviceCount = CFArrayGetCount(list)
        for i in 0..<deviceCount {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let ref = unsafeBitCast(raw, to: MTDeviceRef.self)
            _ = MTRegisterContactFrameCallback(ref, cb)
            _ = MTDeviceStart(ref, 0)
        }
    }

    func currentFingerCount() -> Int32 {
        os_unfair_lock_lock(&lock)
        let value = _fingerCount
        os_unfair_lock_unlock(&lock)
        return value
    }

    func setTapHandler(_ handler: @escaping () -> Void) {
        os_unfair_lock_lock(&lock)
        _tapHandler = handler
        os_unfair_lock_unlock(&lock)
    }

    func notePhysicalThreeFingerClick() {
        let now = DispatchTime.now().uptimeNanoseconds
        os_unfair_lock_lock(&lock)
        _lastPhysicalThreeFingerClickNs = now
        os_unfair_lock_unlock(&lock)
    }

    func hadThreeFingersRecently(within seconds: Double) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let thresholdNs = UInt64(seconds * 1_000_000_000)
        os_unfair_lock_lock(&lock)
        let recent = _lastThreeFingerTimeNs != 0 && (now - _lastThreeFingerTimeNs) <= thresholdNs
        os_unfair_lock_unlock(&lock)
        return recent
    }

    private func updateFingerState(count: Int32, nowNs: UInt64) {
        var fireTap = false
        var tapHandler: (() -> Void)?

        os_unfair_lock_lock(&lock)
        let previousCount = _lastCount
        _fingerCount = count
        _lastCount = count

        // Track a touch sequence from first finger-down until all fingers are up.
        if previousCount == 0 && count > 0 {
            _touchSequenceStartNs = nowNs
            _touchSequenceHadThree = count >= 3
        }

        if count == 3 {
            _lastThreeFingerTimeNs = nowNs
        }
        if count >= 3 {
            _touchSequenceHadThree = true
        }

        // Treat a quick sequence that included 3 fingers as a tap gesture.
        if previousCount > 0 && count == 0 && _touchSequenceStartNs != 0 {
            let durationNs = nowNs - _touchSequenceStartNs
            let tapMaxNs = UInt64(0.25 * 1_000_000_000)
            let suppressAfterPhysicalClickNs = UInt64(0.35 * 1_000_000_000)
            let afterPhysicalClick =
                _lastPhysicalThreeFingerClickNs != 0 &&
                (nowNs - _lastPhysicalThreeFingerClickNs) <= suppressAfterPhysicalClickNs

            if _touchSequenceHadThree && durationNs <= tapMaxNs && !afterPhysicalClick {
                fireTap = true
                tapHandler = _tapHandler
            }
            _touchSequenceStartNs = 0
            _touchSequenceHadThree = false
        }
        os_unfair_lock_unlock(&lock)

        if fireTap, let tapHandler {
            tapHandler()
        }
    }
}

final class MiddleClickMapper {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var sendingMiddleSequence = false

    func start() {
        FingerTracker.shared.start()
        FingerTracker.shared.setTapHandler { [weak self] in
            guard let self else { return }
            self.sendMiddleClickAtPointer()
        }

        let mask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                let mapper = Unmanaged<MiddleClickMapper>
                    .fromOpaque(userInfo!)
                    .takeUnretainedValue()
                return mapper.handle(type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(
                Unmanaged.passUnretained(self).toOpaque()
            )
        )

        guard let tap else {
            fputs("Failed to create event tap. Grant Accessibility access.\n", stderr)
            exit(1)
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("MiddleClick running: 3-finger click/tap -> middle click")
        CFRunLoopRun()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let isLeftDown = type == .leftMouseDown
        let isLeftUp = type == .leftMouseUp

        let isThreeFingerClick = FingerTracker.shared.currentFingerCount() == 3
        let isRecentThreeFingerTap = FingerTracker.shared.hadThreeFingersRecently(within: 0.14)

        if isLeftDown && (isThreeFingerClick || isRecentThreeFingerTap) {
            sendMiddleEventPair(from: event)
            FingerTracker.shared.notePhysicalThreeFingerClick()
            sendingMiddleSequence = true
            return nil
        }

        if isLeftUp && sendingMiddleSequence {
            sendingMiddleSequence = false
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func sendMiddleEventPair(from original: CGEvent) {
        let location = original.location
        sendMiddleEventPair(at: location)
    }

    private func sendMiddleClickAtPointer() {
        guard let event = CGEvent(source: nil) else { return }
        sendMiddleEventPair(at: event.location)
    }

    private func sendMiddleEventPair(at location: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        )
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        )
        down?.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        up?.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

@main
struct MiddleClick {
    static func main() {
        // AppKit permission prompts and event taps behave more reliably
        // from a regular process with an NSApplication instance.
        _ = NSApplication.shared
        MiddleClickMapper().start()
    }
}
