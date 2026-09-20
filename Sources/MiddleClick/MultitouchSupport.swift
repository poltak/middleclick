import CoreFoundation
import Foundation
import os.lock

typealias MTDeviceRef = OpaquePointer

private struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

/// The 96-byte contact record used by MultitouchSupport.framework.
private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: UInt32
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

private typealias MTContactCallback = @convention(c) (
    MTDeviceRef?,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Void

@_silgen_name("MTDeviceCreateList")
private func MTDeviceCreateList() -> CFArray

@_silgen_name("MTRegisterContactFrameCallback")
private func MTRegisterContactFrameCallback(
    _ device: MTDeviceRef,
    _ callback: MTContactCallback
)

@_silgen_name("MTUnregisterContactFrameCallback")
private func MTUnregisterContactFrameCallback(
    _ device: MTDeviceRef,
    _ callback: MTContactCallback
)

@_silgen_name("MTDeviceStart")
private func MTDeviceStart(_ device: MTDeviceRef, _ mode: Int32) -> Int32

@_silgen_name("MTDeviceStop")
private func MTDeviceStop(_ device: MTDeviceRef) -> Int32

final class TouchInputController: @unchecked Sendable {
    static let shared = TouchInputController()

    private struct PendingTap {
        let id: UInt64
        let deadline: TimeInterval
    }

    private var lock = os_unfair_lock_s()
    private var running = false
    private var retainedDeviceList: CFArray?
    private var devices: [MTDeviceRef] = []
    private var recognizers: [UInt: ThreeFingerGestureRecognizer] = [:]
    private var tapHandler: (() -> Void)?
    private var pendingTap: PendingTap?
    private var nextTapID: UInt64 = 0

    private static let callback: MTContactCallback = { device, touches, count, _, _ in
        guard let device else { return }
        TouchInputController.shared.receive(device: device, touches: touches, count: count)
    }

    private init() {
        precondition(MemoryLayout<MTTouch>.size == 96, "Unexpected MTTouch layout")
    }

    func start(onTap: @escaping () -> Void) {
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
        pendingTap = nil
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

        let newList = MTDeviceCreateList()
        var newDevices: [MTDeviceRef] = []
        for index in 0..<CFArrayGetCount(newList) {
            guard let raw = CFArrayGetValueAtIndex(newList, index) else { continue }
            newDevices.append(unsafeBitCast(raw, to: MTDeviceRef.self))
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
        recognizers = Dictionary(
            uniqueKeysWithValues: newDevices.map {
                (Self.deviceKey($0), ThreeFingerGestureRecognizer())
            }
        )
        os_unfair_lock_unlock(&lock)

        for device in newDevices {
            MTRegisterContactFrameCallback(device, Self.callback)
            _ = MTDeviceStart(device, 0)
        }
    }

    /// Associates a native mouse-down with the touch sequence that produced it.
    /// A just-completed tap is kept briefly so callback ordering cannot duplicate it.
    func claimMouseClick() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for key in recognizers.keys {
            guard let recognizer = recognizers[key] else { continue }
            if recognizer.claimPhysicalClick() {
                pendingTap = nil
                return true
            }
        }

        if let pendingTap, now <= pendingTap.deadline {
            self.pendingTap = nil
            return true
        }
        return false
    }

    private func receive(
        device: MTDeviceRef,
        touches: UnsafeMutableRawPointer?,
        count: Int32
    ) {
        let contactCount = max(0, Int(count))
        var contacts: [TouchContact] = []
        if let touches, contactCount > 0 {
            let typedTouches = touches.assumingMemoryBound(to: MTTouch.self)
            contacts.reserveCapacity(contactCount)
            for touch in UnsafeBufferPointer(start: typedTouches, count: contactCount) {
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

        let now = ProcessInfo.processInfo.systemUptime
        let frame = TouchFrame(time: now, contacts: contacts)
        let key = Self.deviceKey(device)
        var tapID: UInt64?

        os_unfair_lock_lock(&lock)
        if running, let recognizer = recognizers[key] {
            let recognizedTap = recognizer.process(frame)
            if recognizedTap {
                nextTapID &+= 1
                let id = nextTapID
                pendingTap = PendingTap(id: id, deadline: now + 0.035)
                tapID = id
            }
        }
        os_unfair_lock_unlock(&lock)

        if let tapID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
                self?.firePendingTap(id: tapID)
            }
        }
    }

    private func firePendingTap(id: UInt64) {
        var handler: (() -> Void)?
        os_unfair_lock_lock(&lock)
        if running, pendingTap?.id == id {
            pendingTap = nil
            handler = tapHandler
        }
        os_unfair_lock_unlock(&lock)
        handler?()
    }

    private static func deviceKey(_ device: MTDeviceRef) -> UInt {
        UInt(bitPattern: device)
    }
}
