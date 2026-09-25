import Foundation

struct GestureTraceContact: Codable, Equatable, Sendable {
    let fingerID: Int32
    let state: UInt32
    let normalizedX: Float
    let normalizedY: Float
    let active: Bool
}

struct GestureTraceEvent: Codable, Equatable, Sendable {
    var timeSeconds: Double
    var inputTimeSeconds: Double? = nil
    var frameSequence: UInt64? = nil
    let kind: String
    var device: String? = nil
    var callbackContactCount: Int? = nil
    var activeContactCount: Int? = nil
    var contacts: [GestureTraceContact]? = nil
    var tapAccepted: Bool? = nil
    var edgeOutlierPairDistance: Float? = nil
    var edgeOutlierDistance: Float? = nil
    var edgeOutlierDistanceThreshold: Float? = nil
    var edgeOutlierBoundaryBand: Float? = nil
    var edgeOutlierClosestPairUnique: Bool? = nil
    var edgeOutlierContactAtBoundary: Bool? = nil
    var edgeOutlierRejected: Bool? = nil
    var tapID: UInt64? = nil
    var source: String? = nil
    var button: String? = nil
    var mappingAllowed: Bool? = nil
    var physicalClickMappingAllowed: Bool? = nil
    var mapperEnabled: Bool? = nil
    var claimed: Bool? = nil
    var suppressed: Bool? = nil
    var scrollDeltaX: Int64? = nil
    var scrollDeltaY: Int64? = nil

    init(kind: String, timeSeconds: Double = 0) {
        self.kind = kind
        self.timeSeconds = timeSeconds
    }
}

struct GestureTraceSettings: Codable, Equatable, Sendable {
    let mapperEnabled: Bool
    let tapMappingAllowed: Bool
    let physicalClickMappingAllowed: Bool
}

struct GestureTraceRecording: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let appVersion: String
    let appBuild: String
    let operatingSystem: String
    let windowSeconds: Double
    let durationSeconds: Double
    let eventLimit: Int
    let droppedEventCount: Int
    let truncatedContactFrameCount: Int
    let currentMappingSettings: GestureTraceSettings?
    let events: [GestureTraceEvent]
}

struct GestureTraceBuffer {
    static let defaultWindowSeconds = 30.0
    static let defaultEventLimit = 4_096
    static let maxContactsPerFrame = 32
    private static let maxDeviceLabels = 16

    private let windowSeconds: Double
    private let eventLimit: Int
    private var slots: [GestureTraceEvent?]
    private var head = 0
    private var count = 0
    private var startedAt: Double?
    private var latestTime = 0.0
    private var recording = false
    private var droppedEventCount = 0
    private var truncatedContactFrameCount = 0
    private var deviceLabels: [UInt: String] = [:]
    private var currentMappingSettings: GestureTraceSettings?

    init(windowSeconds: Double = defaultWindowSeconds, eventLimit: Int = defaultEventLimit) {
        precondition(windowSeconds > 0)
        precondition(eventLimit > 0)
        self.windowSeconds = windowSeconds
        self.eventLimit = eventLimit
        slots = Array(repeating: nil, count: eventLimit)
    }

    var isRecording: Bool { recording }
    var hasRecording: Bool { !recording && count > 0 }

    mutating func start(at uptime: Double) {
        reset()
        startedAt = uptime
        recording = true
        append(GestureTraceEvent(kind: "recordingStarted"), at: uptime)
    }

    mutating func stop(at uptime: Double) {
        guard recording else { return }
        append(GestureTraceEvent(kind: "recordingStopped"), at: uptime)
        recording = false
        prune(before: latestTime - windowSeconds)
    }

    mutating func append(
        _ event: GestureTraceEvent,
        at uptime: Double,
        deviceKey: UInt? = nil,
        truncatedContacts: Bool = false
    ) {
        guard recording, let startedAt else { return }
        var event = event
        event.inputTimeSeconds = max(0, uptime - startedAt)
        event.timeSeconds = max(latestTime, event.inputTimeSeconds ?? 0)
        if event.kind == "mappingSettings",
           let mapperEnabled = event.mapperEnabled,
           let tapMappingAllowed = event.mappingAllowed,
           let physicalClickMappingAllowed = event.physicalClickMappingAllowed
        {
            currentMappingSettings = GestureTraceSettings(
                mapperEnabled: mapperEnabled,
                tapMappingAllowed: tapMappingAllowed,
                physicalClickMappingAllowed: physicalClickMappingAllowed
            )
        }
        if let deviceKey {
            event.device = label(for: deviceKey)
        }
        if truncatedContacts {
            truncatedContactFrameCount += 1
        }

        prune(before: event.timeSeconds - windowSeconds)
        if count == eventLimit {
            removeFirst()
            droppedEventCount += 1
        }
        slots[(head + count) % eventLimit] = event
        count += 1
        latestTime = event.timeSeconds
    }

    func snapshot() -> GestureTraceRecording? {
        guard hasRecording, startedAt != nil else { return nil }
        let events = (0..<count).compactMap { slots[(head + $0) % eventLimit] }
        return GestureTraceRecording(
            schemaVersion: 1,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            windowSeconds: windowSeconds,
            durationSeconds: min(windowSeconds, latestTime),
            eventLimit: eventLimit,
            droppedEventCount: droppedEventCount,
            truncatedContactFrameCount: truncatedContactFrameCount,
            currentMappingSettings: currentMappingSettings,
            events: events
        )
    }

    mutating func clear() {
        reset()
    }

    private mutating func reset() {
        slots = Array(repeating: nil, count: eventLimit)
        head = 0
        count = 0
        startedAt = nil
        latestTime = 0
        recording = false
        droppedEventCount = 0
        truncatedContactFrameCount = 0
        deviceLabels.removeAll(keepingCapacity: true)
        currentMappingSettings = nil
    }

    private mutating func label(for deviceKey: UInt) -> String {
        if let label = deviceLabels[deviceKey] { return label }
        guard deviceLabels.count < Self.maxDeviceLabels else { return "D+" }
        let label = "D\(deviceLabels.count + 1)"
        deviceLabels[deviceKey] = label
        return label
    }

    private mutating func prune(before cutoff: Double) {
        while count > 0,
              let first = slots[head],
              first.timeSeconds < cutoff
        {
            removeFirst()
            droppedEventCount += 1
        }
    }

    private mutating func removeFirst() {
        slots[head] = nil
        head = (head + 1) % eventLimit
        count -= 1
    }
}

final class GestureTraceRecorder: @unchecked Sendable {
    static let shared = GestureTraceRecorder()

    private let lock = NSLock()
    private var buffer = GestureTraceBuffer()

    private init() {}

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.isRecording
    }

    var hasRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.hasRecording
    }

    func start() {
        lock.lock()
        buffer.start(at: ProcessInfo.processInfo.systemUptime)
        lock.unlock()
    }

    func stop() {
        lock.lock()
        buffer.stop(at: ProcessInfo.processInfo.systemUptime)
        lock.unlock()
    }

    func recordingData() throws -> Data? {
        lock.lock()
        let snapshot = buffer.snapshot()
        lock.unlock()
        guard let snapshot else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    func clear() {
        lock.lock()
        buffer.clear()
        lock.unlock()
    }

    func recordFrame(
        at uptime: Double,
        deviceKey: UInt,
        callbackContactCount: Int,
        activeContactCount: Int,
        contacts: [GestureTraceContact],
        edgeOutlierAssessment: EdgeOutlierAssessment?,
        tapAccepted: Bool,
        tapID: UInt64?,
        frameSequence: UInt64,
        registeredDevice: Bool
    ) {
        guard isRecording else { return }
        var event = GestureTraceEvent(kind: "touchFrame")
        event.callbackContactCount = callbackContactCount
        event.activeContactCount = activeContactCount
        event.contacts = Array(contacts.prefix(GestureTraceBuffer.maxContactsPerFrame))
        if let edgeOutlierAssessment {
            event.edgeOutlierPairDistance = edgeOutlierAssessment.closestPairDistance
            event.edgeOutlierDistance = edgeOutlierAssessment.outlierDistance
            event.edgeOutlierDistanceThreshold = edgeOutlierAssessment.distanceThreshold
            event.edgeOutlierBoundaryBand = edgeOutlierAssessment.boundaryBand
            event.edgeOutlierClosestPairUnique = edgeOutlierAssessment.closestPairIsUnique
            event.edgeOutlierContactAtBoundary = edgeOutlierAssessment.contactAtBoundary
            event.edgeOutlierRejected = edgeOutlierAssessment.rejected
        }
        event.tapAccepted = tapAccepted
        event.tapID = tapID
        event.frameSequence = frameSequence
        event.source = registeredDevice ? "registeredDevice" : "unmatchedDevice"
        lock.lock()
        buffer.append(
            event,
            at: uptime,
            deviceKey: deviceKey,
            truncatedContacts: callbackContactCount > contacts.count
        )
        lock.unlock()
    }

    func recordClickClaim(at uptime: Double, deviceKey: UInt?, tapID: UInt64?, source: String) {
        var event = GestureTraceEvent(kind: "nativeClickClaim")
        event.tapID = tapID
        event.source = source
        event.claimed = true
        append(event, at: uptime, deviceKey: deviceKey)
    }

    func recordMouseButton(
        at uptime: Double,
        stage: String,
        button: String,
        mappingAllowed: Bool,
        claimed: Bool,
        tapID: UInt64? = nil,
        source: String? = nil,
        suppressed: Bool
    ) {
        var event = GestureTraceEvent(kind: "nativeMouseButton")
        event.source = source ?? stage
        event.button = button
        event.mappingAllowed = mappingAllowed
        event.claimed = claimed
        event.tapID = tapID
        event.suppressed = suppressed
        append(event, at: uptime)
    }

    func recordTapOutput(at uptime: Double, tapID: UInt64, emitted: Bool, reason: String? = nil) {
        var event = GestureTraceEvent(kind: "tapOutput")
        event.tapID = tapID
        event.source = emitted ? "syntheticMiddleClick" : (reason ?? "suppressed")
        event.suppressed = !emitted
        append(event, at: uptime)
    }

    func recordScroll(at uptime: Double, deltaX: Int64, deltaY: Int64) {
        var event = GestureTraceEvent(kind: "scrollWheel")
        event.scrollDeltaX = deltaX
        event.scrollDeltaY = deltaY
        append(event, at: uptime)
    }

    func recordSettings(
        at uptime: Double,
        mapperEnabled: Bool,
        tapMappingAllowed: Bool,
        physicalClickMappingAllowed: Bool
    ) {
        var event = GestureTraceEvent(kind: "mappingSettings")
        event.mapperEnabled = mapperEnabled
        event.mappingAllowed = tapMappingAllowed
        event.physicalClickMappingAllowed = physicalClickMappingAllowed
        append(event, at: uptime)
    }

    private func append(_ event: GestureTraceEvent, at uptime: Double, deviceKey: UInt? = nil) {
        guard isRecording else { return }
        lock.lock()
        buffer.append(event, at: uptime, deviceKey: deviceKey)
        lock.unlock()
    }
}
