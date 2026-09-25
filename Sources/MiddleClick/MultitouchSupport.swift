import CoreFoundation
import Foundation
import MultitouchSupportShim
import os
import os.lock

struct TouchInputDiagnostics: Sendable {
    let deviceCount: Int
    let startedDeviceCount: Int
    let callbackFrameCount: UInt64
    let unmatchedFrameCount: UInt64
    let activeContactCount: Int
    let recognizedTapCount: UInt64
}

struct NativeClickClaim: Sendable {
    let source: String
    let deviceKey: UInt?
    let tapID: UInt64?
}

enum TouchContactAdapter {
    static func isTouching(state: UInt32) -> Bool {
        state == MTTouchStateMakeTouch || state == MTTouchStateTouching
    }
}

struct PendingTapCoordinator: Sendable {
    struct PendingTap: Sendable {
        let id: UInt64
        let deadline: TimeInterval
        let deviceKey: UInt?
    }

    private(set) var pending: [PendingTap] = []
    private var nextID: UInt64 = 0

    mutating func schedule(at time: TimeInterval, delay: TimeInterval, deviceKey: UInt? = nil) -> UInt64 {
        nextID &+= 1
        pending.append(PendingTap(id: nextID, deadline: time + delay, deviceKey: deviceKey))
        return nextID
    }

    mutating func claim(at time: TimeInterval) -> Bool {
        claimPending(at: time) != nil
    }

    mutating func claimPending(at time: TimeInterval) -> PendingTap? {
        pending.removeAll { $0.deadline < time }
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    mutating func fire(id: UInt64) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
        pending.remove(at: index)
        return true
    }

    mutating func cancelAll() {
        pending.removeAll()
    }
}

final class TouchInputController: @unchecked Sendable {
    static let shared = TouchInputController()
    private static let logger = Logger(subsystem: "com.jon.middleclick", category: "touch-input")
    private static let nativeTapCoordinationDelay: TimeInterval = 0.12

    private var lock = os_unfair_lock_s()
    private var running = false
    private var retainedDeviceList: CFArray?
    private var devices: [MTDeviceRef] = []
    private var recognizers: [UInt: ThreeFingerGestureRecognizer] = [:]
    private var tapHandler: ((UInt64) -> Void)?
    private var tapCoordinator = PendingTapCoordinator()
    private var startedDeviceCount = 0
    private var callbackFrameCount: UInt64 = 0
    private var unmatchedFrameCount: UInt64 = 0
    private var activeContactCount = 0
    private var recognizedTapCount: UInt64 = 0

    private static let callback: MTFrameCallbackFunction = { device, touches, count, _, _ in
        guard let device else { return }
        TouchInputController.shared.receive(device: device, touches: touches, count: count)
    }

    private init() {
        precondition(MemoryLayout<MTTouch>.size == 96, "Unexpected MTTouch layout")
    }

    func start(onTap: @escaping (UInt64) -> Void) {
        os_unfair_lock_lock(&lock)
        tapHandler = onTap
        let wasRunning = running
        running = true
        os_unfair_lock_unlock(&lock)

        if !wasRunning {
            refreshDevices()
        }
    }

    func stop() {
        os_unfair_lock_lock(&lock)
        running = false
        tapHandler = nil
        tapCoordinator.cancelAll()
        startedDeviceCount = 0
        activeContactCount = 0
        let devicesToStop = devices
        let deviceListToRelease = retainedDeviceList
        devices = []
        recognizers = [:]
        retainedDeviceList = nil
        os_unfair_lock_unlock(&lock)

        for device in devicesToStop {
            MTUnregisterContactFrameCallback(device, Self.callback)
            _ = MTDeviceStop(device)
        }
        withExtendedLifetime(deviceListToRelease) {}
    }

    /// Re-enumerates devices after wake and while a trackpad is connected or removed.
    func refreshDevices() {
        os_unfair_lock_lock(&lock)
        let shouldRun = running
        os_unfair_lock_unlock(&lock)
        guard shouldRun else { return }

        guard let newListHandle = MTDeviceCreateList() else {
            Self.logger.error("MTDeviceCreateList returned nil")
            return
        }
        let newList = newListHandle.takeRetainedValue()
        var newDevices: [MTDeviceRef] = []
        for index in 0..<CFArrayGetCount(newList) {
            guard let raw = CFArrayGetValueAtIndex(newList, index) else { continue }
            newDevices.append(raw)
        }

        let newKeys = Set(newDevices.map(Self.deviceKey))
        os_unfair_lock_lock(&lock)
        let oldKeys = Set(devices.map(Self.deviceKey))
        let oldDevices = devices
        let oldDeviceList = retainedDeviceList
        os_unfair_lock_unlock(&lock)
        guard newKeys != oldKeys else { return }

        for device in oldDevices {
            MTUnregisterContactFrameCallback(device, Self.callback)
            _ = MTDeviceStop(device)
        }
        withExtendedLifetime(oldDeviceList) {}

        os_unfair_lock_lock(&lock)
        guard running else {
            os_unfair_lock_unlock(&lock)
            return
        }
        retainedDeviceList = newList
        devices = newDevices
        startedDeviceCount = 0
        recognizers = Dictionary(
            uniqueKeysWithValues: newDevices.map {
                (Self.deviceKey($0), ThreeFingerGestureRecognizer())
            }
        )
        os_unfair_lock_unlock(&lock)

        for device in newDevices {
            MTRegisterContactFrameCallback(device, Self.callback)
            let result = MTDeviceStart(device, 0)
            os_unfair_lock_lock(&lock)
            if result == 0 {
                startedDeviceCount += 1
            }
            os_unfair_lock_unlock(&lock)
            if result != 0 {
                Self.logger.error("MTDeviceStart failed with status \(result)")
            }
        }
        Self.logger.info(
            "Registered \(newDevices.count) multitouch device(s); \(self.diagnostics().startedDeviceCount) started"
        )
    }

    func diagnostics() -> TouchInputDiagnostics {
        os_unfair_lock_lock(&lock)
        let snapshot = TouchInputDiagnostics(
            deviceCount: devices.count,
            startedDeviceCount: startedDeviceCount,
            callbackFrameCount: callbackFrameCount,
            unmatchedFrameCount: unmatchedFrameCount,
            activeContactCount: activeContactCount,
            recognizedTapCount: recognizedTapCount
        )
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    /// Associates a native mouse-down with the touch sequence that produced it.
    /// A just-completed tap is kept briefly so callback ordering cannot duplicate it.
    func claimMouseClick() -> NativeClickClaim? {
        let now = ProcessInfo.processInfo.systemUptime
        os_unfair_lock_lock(&lock)
        var claim: NativeClickClaim?
        for key in recognizers.keys {
            guard let recognizer = recognizers[key] else { continue }
            if recognizer.claimPhysicalClick() {
                claim = NativeClickClaim(source: "activeTouchSequence", deviceKey: key, tapID: nil)
                break
            }
        }
        if claim == nil, let pendingTap = tapCoordinator.claimPending(at: now) {
            claim = NativeClickClaim(
                source: "pendingTap",
                deviceKey: pendingTap.deviceKey,
                tapID: pendingTap.id
            )
        }
        os_unfair_lock_unlock(&lock)

        if let claim {
            GestureTraceRecorder.shared.recordClickClaim(
                at: now,
                deviceKey: claim.deviceKey,
                tapID: claim.tapID,
                source: claim.source
            )
        }
        return claim
    }

    private func receive(
        device: MTDeviceRef,
        touches: UnsafeMutablePointer<MTTouch>?,
        count: Int
    ) {
        let contactCount = max(0, count)
        var contacts: [TouchContact] = []
        let captureTrace = GestureTraceRecorder.shared.isRecording
        var traceContacts: [GestureTraceContact] = []
        if let touches, contactCount > 0 {
            contacts.reserveCapacity(contactCount)
            if captureTrace {
                traceContacts.reserveCapacity(min(contactCount, GestureTraceBuffer.maxContactsPerFrame))
            }
            for touch in UnsafeBufferPointer(start: touches, count: contactCount) {
                let active = TouchContactAdapter.isTouching(state: touch.state)
                if captureTrace, traceContacts.count < GestureTraceBuffer.maxContactsPerFrame {
                    traceContacts.append(
                        GestureTraceContact(
                            fingerID: touch.fingerID,
                            state: touch.state,
                            normalizedX: touch.normalizedVector.position.x,
                            normalizedY: touch.normalizedVector.position.y,
                            active: active
                        )
                    )
                }
                if active {
                    contacts.append(
                        TouchContact(
                            id: touch.fingerID,
                            position: .init(
                                touch.normalizedVector.position.x,
                                touch.normalizedVector.position.y
                            )
                        )
                    )
                }
            }
        }

        let now = ProcessInfo.processInfo.systemUptime
        let frame = TouchFrame(time: now, contacts: contacts)
        let key = Self.deviceKey(device)
        let edgeOutlierAssessment = captureTrace
            ? EdgeOutlierAssessment.assess(
                contacts: contacts,
                configuration: GestureConfiguration()
            )
            : nil
        var tapID: UInt64?
        var recognizedTap = false
        var registeredDevice = false
        var frameSequence: UInt64 = 0

        os_unfair_lock_lock(&lock)
        callbackFrameCount &+= 1
        frameSequence = callbackFrameCount
        activeContactCount = contacts.count
        if running, let recognizer = recognizers[key] {
            registeredDevice = true
            recognizedTap = recognizer.process(frame)
            if recognizedTap {
                recognizedTapCount &+= 1
                let id = tapCoordinator.schedule(
                    at: now,
                    delay: Self.nativeTapCoordinationDelay,
                    deviceKey: key
                )
                tapID = id
            }
        } else if running {
            unmatchedFrameCount &+= 1
            if unmatchedFrameCount == 1 {
                Self.logger.error("Received a frame for an unregistered multitouch device")
            }
        }
        os_unfair_lock_unlock(&lock)

        if captureTrace {
            GestureTraceRecorder.shared.recordFrame(
                at: now,
                deviceKey: key,
                callbackContactCount: contactCount,
                activeContactCount: contacts.count,
                contacts: traceContacts,
                edgeOutlierAssessment: edgeOutlierAssessment,
                tapAccepted: recognizedTap,
                tapID: tapID,
                frameSequence: frameSequence,
                registeredDevice: registeredDevice
            )
        }

        if let tapID {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.nativeTapCoordinationDelay
            ) { [weak self] in
                self?.firePendingTap(id: tapID)
            }
        }
    }

    private func firePendingTap(id: UInt64) {
        var handler: ((UInt64) -> Void)?
        os_unfair_lock_lock(&lock)
        if running, tapCoordinator.fire(id: id) {
            handler = tapHandler
        }
        os_unfair_lock_unlock(&lock)
        handler?(id)
    }

    private static func deviceKey(_ device: MTDeviceRef) -> UInt {
        UInt(bitPattern: device)
    }
}
