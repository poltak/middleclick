import Foundation
import Testing
@testable import MiddleClick

@Suite("Gesture trace recording")
struct GestureTraceRecorderTests {
    @Test func disabledBufferDoesNotCaptureEvents() {
        var buffer = GestureTraceBuffer(eventLimit: 8)
        buffer.append(GestureTraceEvent(kind: "ignored"), at: 1)
        #expect(buffer.snapshot() == nil)

        buffer.start(at: 10)
        buffer.append(GestureTraceEvent(kind: "touchFrame"), at: 11)
        buffer.stop(at: 12)

        #expect(!buffer.isRecording)
        #expect(buffer.hasRecording)
        #expect(buffer.snapshot()?.events.map(\.kind) == [
            "recordingStarted", "touchFrame", "recordingStopped",
        ])
    }

    @Test func timeWindowEvictsOldFrames() {
        var buffer = GestureTraceBuffer(windowSeconds: 2, eventLimit: 10)
        buffer.start(at: 10)
        buffer.append(GestureTraceEvent(kind: "early"), at: 10.5)
        buffer.append(GestureTraceEvent(kind: "edge"), at: 11.1)
        buffer.append(GestureTraceEvent(kind: "latest"), at: 13)
        buffer.stop(at: 13.1)

        let recording = buffer.snapshot()
        #expect(recording?.events.map(\.kind) == ["edge", "latest", "recordingStopped"])
        #expect(recording?.events.allSatisfy { $0.timeSeconds >= 1.09 } == true)
        #expect(recording?.droppedEventCount == 2)
    }

    @Test func hardEventCapEvictsOldestEntry() {
        var buffer = GestureTraceBuffer(eventLimit: 3)
        buffer.start(at: 0)
        buffer.append(GestureTraceEvent(kind: "one"), at: 1)
        buffer.append(GestureTraceEvent(kind: "two"), at: 2)
        buffer.append(GestureTraceEvent(kind: "three"), at: 3)
        buffer.stop(at: 3.01)

        let recording = buffer.snapshot()
        #expect(recording?.events.count == 3)
        #expect(recording?.events.map(\.kind) == ["two", "three", "recordingStopped"])
        #expect(recording?.droppedEventCount == 2)
    }

    @Test func exportKeepsOrderedAndOriginalRelativeTimesAndMetadata() throws {
        var buffer = GestureTraceBuffer()
        buffer.start(at: 100)

        var later = GestureTraceEvent(kind: "touchFrame")
        later.frameSequence = 20
        buffer.append(later, at: 102, deviceKey: 99)

        var earlier = GestureTraceEvent(kind: "touchFrame")
        earlier.frameSequence = 21
        earlier.contacts = [
            GestureTraceContact(
                fingerID: 4,
                state: 2,
                normalizedX: 0.25,
                normalizedY: 0.75,
                active: false
            ),
        ]
        buffer.append(earlier, at: 101, deviceKey: 99)

        var settings = GestureTraceEvent(kind: "mappingSettings")
        settings.mapperEnabled = true
        settings.mappingAllowed = false
        settings.physicalClickMappingAllowed = true
        buffer.append(settings, at: 102.1)
        buffer.stop(at: 102.2)

        let snapshot = try #require(buffer.snapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(GestureTraceRecording.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.events.map(\.timeSeconds) == decoded.events.map(\.timeSeconds).sorted())
        #expect(decoded.events[2].inputTimeSeconds == 1)
        #expect(decoded.events[2].frameSequence == 21)
        #expect(decoded.events[1].device == "D1")
        #expect(decoded.events[2].contacts?.first?.state == 2)
        #expect(decoded.events[2].contacts?.first?.normalizedX == 0.25)
        #expect(decoded.currentMappingSettings == GestureTraceSettings(
            mapperEnabled: true,
            tapMappingAllowed: false,
            physicalClickMappingAllowed: true
        ))
        #expect(decoded.appVersion.isEmpty == false)
        #expect(decoded.operatingSystem.isEmpty == false)
    }

    @Test func exportedFramesKeepEdgeOutlierScoresAndDecisions() throws {
        let recorder = GestureTraceRecorder.shared
        recorder.clear()
        recorder.start()
        defer {
            recorder.stop()
            recorder.clear()
        }

        let configuration = GestureConfiguration()
        let rejectedContacts = [
            TouchContact(id: 1, position: .init(0.64, 0.81)),
            TouchContact(id: 2, position: .init(0.78, 0.72)),
            TouchContact(id: 3, position: .init(1.00, 0.05)),
        ]
        let normalContacts = [
            TouchContact(id: 4, position: .init(0.20, 0.30)),
            TouchContact(id: 5, position: .init(0.24, 0.30)),
            TouchContact(id: 6, position: .init(0.55, 0.30)),
        ]
        let rejectedAssessment = try #require(EdgeOutlierAssessment.assess(
            contacts: rejectedContacts,
            configuration: configuration
        ))
        let normalAssessment = try #require(EdgeOutlierAssessment.assess(
            contacts: normalContacts,
            configuration: configuration
        ))

        func traceContacts(_ contacts: [TouchContact]) -> [GestureTraceContact] {
            contacts.map {
                GestureTraceContact(
                    fingerID: $0.id,
                    state: 4,
                    normalizedX: $0.position.x,
                    normalizedY: $0.position.y,
                    active: true
                )
            }
        }

        let deviceKey: UInt = 123
        recorder.recordFrame(
            at: ProcessInfo.processInfo.systemUptime,
            deviceKey: deviceKey,
            callbackContactCount: 3,
            activeContactCount: 3,
            contacts: traceContacts(rejectedContacts),
            edgeOutlierAssessment: rejectedAssessment,
            tapAccepted: false,
            tapID: nil,
            frameSequence: 1,
            registeredDevice: true
        )
        recorder.recordFrame(
            at: ProcessInfo.processInfo.systemUptime,
            deviceKey: deviceKey,
            callbackContactCount: 3,
            activeContactCount: 3,
            contacts: traceContacts(normalContacts),
            edgeOutlierAssessment: normalAssessment,
            tapAccepted: false,
            tapID: nil,
            frameSequence: 2,
            registeredDevice: true
        )
        recorder.stop()

        let exportedData = try recorder.recordingData()
        let data = try #require(exportedData)
        let recording = try JSONDecoder().decode(GestureTraceRecording.self, from: data)
        let frames = recording.events.filter { $0.kind == "touchFrame" }
        #expect(frames.count == 2)

        let edgeFrame = try #require(frames.first)
        #expect(edgeFrame.edgeOutlierPairDistance != nil)
        #expect((edgeFrame.edgeOutlierDistance ?? 0) > 0.30)
        #expect(edgeFrame.edgeOutlierDistanceThreshold == 0.30)
        #expect(edgeFrame.edgeOutlierBoundaryBand == 0.01)
        #expect(edgeFrame.edgeOutlierClosestPairUnique == true)
        #expect(edgeFrame.edgeOutlierContactAtBoundary == true)
        #expect(edgeFrame.edgeOutlierRejected == true)

        let normalFrame = try #require(frames.last)
        #expect(normalFrame.edgeOutlierClosestPairUnique == true)
        #expect((normalFrame.edgeOutlierDistance ?? 0) > 0.30)
        #expect(normalFrame.edgeOutlierContactAtBoundary == false)
        #expect(normalFrame.edgeOutlierRejected == false)
    }

    @Test func restartClearsPreviousSessionAndDeviceLabels() throws {
        var buffer = GestureTraceBuffer(eventLimit: 4)
        buffer.start(at: 1)
        buffer.append(GestureTraceEvent(kind: "old"), at: 2, deviceKey: 100)
        buffer.append(GestureTraceEvent(kind: "older"), at: 2.1, deviceKey: 100)
        buffer.append(GestureTraceEvent(kind: "oldest"), at: 2.2, deviceKey: 100)
        buffer.stop(at: 3)
        #expect(buffer.snapshot()?.droppedEventCount == 1)

        buffer.start(at: 20)
        buffer.append(GestureTraceEvent(kind: "new"), at: 21, deviceKey: 200)
        buffer.stop(at: 22)
        let recording = try #require(buffer.snapshot())

        #expect(recording.events.map(\.kind) == ["recordingStarted", "new", "recordingStopped"])
        #expect(recording.events[1].device == "D1")
        #expect(recording.droppedEventCount == 0)
        #expect(recording.currentMappingSettings == nil)
    }

    @Test func exportedFramesReplayBothTwoFingerAndTransientThirdContactCases() throws {
        let twoFingerFrames = [
            frame(0, contact(1, x: 0.2), contact(2, x: 0.4)),
            frame(0.08, contact(1, x: 0.32), contact(2, x: 0.52)),
            frame(0.12),
        ]
        let transientThirdContactFrames = [
            twoFingerFrames[0],
            twoFingerFrames[1],
            frame(0.10, contact(1, x: 0.32), contact(2, x: 0.52), contact(3, x: 0.7)),
            frame(0.12),
        ]

        let twoFingerResult = try recordAndReplay(twoFingerFrames)
        let transientThirdResult = try recordAndReplay(transientThirdContactFrames)

        #expect(twoFingerResult.recorded == twoFingerResult.replayed)
        #expect(twoFingerResult.replayed.last == false)
        #expect(transientThirdResult.recorded == transientThirdResult.replayed)
        #expect(transientThirdResult.replayed.last == true)
    }

    private func recordAndReplay(_ frames: [TouchFrame]) throws -> (recorded: [Bool], replayed: [Bool]) {
        let baseTime = 100.0
        var buffer = GestureTraceBuffer()
        buffer.start(at: baseTime)
        let recognizer = ThreeFingerGestureRecognizer()
        var recorded: [Bool] = []

        for (index, frame) in frames.enumerated() {
            let accepted = recognizer.process(frame)
            recorded.append(accepted)
            var event = GestureTraceEvent(kind: "touchFrame")
            event.frameSequence = UInt64(index + 1)
            event.callbackContactCount = frame.contacts.count
            event.activeContactCount = frame.contacts.count
            event.tapAccepted = accepted
            event.contacts = frame.contacts.map {
                GestureTraceContact(
                    fingerID: $0.id,
                    state: 4,
                    normalizedX: $0.position.x,
                    normalizedY: $0.position.y,
                    active: true
                )
            }
            buffer.append(event, at: baseTime + frame.time, deviceKey: 1)
        }
        buffer.stop(at: baseTime + 0.13)

        let snapshot = try #require(buffer.snapshot())
        let data = try JSONEncoder().encode(snapshot)
        let exported = try JSONDecoder().decode(GestureTraceRecording.self, from: data)
        let replayRecognizer = ThreeFingerGestureRecognizer()
        let replayed = exported.events
            .filter { $0.kind == "touchFrame" }
            .map { event in
                let contacts = event.contacts?.filter(\.active).map {
                    TouchContact(id: $0.fingerID, position: .init($0.normalizedX, $0.normalizedY))
                } ?? []
                return replayRecognizer.process(
                    TouchFrame(time: event.inputTimeSeconds ?? 0, contacts: contacts)
                )
            }

        return (recorded, replayed)
    }

    private func frame(_ time: Double, _ contacts: TouchContact...) -> TouchFrame {
        TouchFrame(time: time, contacts: contacts)
    }

    private func contact(_ id: Int32, x: Float) -> TouchContact {
        TouchContact(id: id, position: .init(x, 0.2))
    }
}
