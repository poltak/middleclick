import Foundation
import simd

struct TouchContact: Equatable, Sendable {
    let id: Int32
    let position: SIMD2<Float>
}

struct TouchFrame: Equatable, Sendable {
    let time: TimeInterval
    let contacts: [TouchContact]
}

struct GestureConfiguration: Equatable, Sendable {
    var fingerCount = 3
    var maximumDuration: TimeInterval = 0.30
    var maximumFingerArrivalInterval: TimeInterval = 0.18
    var maximumMovement: Float = 0.045
}

/// Recognizes one complete gesture on one physical multitouch device.
final class ThreeFingerGestureRecognizer: @unchecked Sendable {
    private struct Sequence: Sendable {
        let startedAt: TimeInterval
        var origins: [Int32: SIMD2<Float>]
        var currentContactCount: Int
        var reachedRequiredCount = false
        var maximumContactCount: Int
        var invalid = false
        var consumedByMouseClick = false
    }

    private let configuration: GestureConfiguration
    private var sequence: Sequence?

    init(configuration: GestureConfiguration = .init()) {
        self.configuration = configuration
    }

    var hasClaimablePhysicalClick: Bool {
        guard let sequence else { return false }
        return !sequence.invalid &&
            !sequence.consumedByMouseClick &&
            sequence.currentContactCount == configuration.fingerCount &&
            sequence.maximumContactCount == configuration.fingerCount
    }

    func claimPhysicalClick() -> Bool {
        guard hasClaimablePhysicalClick else { return false }
        sequence?.consumedByMouseClick = true
        return true
    }

    /// Returns true only when this frame completes a valid, unconsumed tap.
    func process(_ frame: TouchFrame) -> Bool {
        if frame.contacts.isEmpty {
            return finish(at: frame.time)
        }

        if sequence == nil {
            sequence = Sequence(
                startedAt: frame.time,
                origins: [:],
                currentContactCount: frame.contacts.count,
                maximumContactCount: frame.contacts.count
            )
        }

        guard var current = sequence else { return false }
        current.currentContactCount = frame.contacts.count
        current.maximumContactCount = max(current.maximumContactCount, frame.contacts.count)

        let elapsed = max(0, frame.time - current.startedAt)
        if elapsed > configuration.maximumDuration ||
            current.maximumContactCount > configuration.fingerCount
        {
            current.invalid = true
        }

        for contact in frame.contacts {
            if let origin = current.origins[contact.id] {
                if simd_distance(origin, contact.position) > configuration.maximumMovement {
                    current.invalid = true
                }
            } else {
                current.origins[contact.id] = contact.position
            }
        }
        if current.origins.count > configuration.fingerCount {
            current.invalid = true
        }

        if frame.contacts.count == configuration.fingerCount {
            if elapsed <= configuration.maximumFingerArrivalInterval {
                current.reachedRequiredCount = true
            } else {
                current.invalid = true
            }
        }

        sequence = current
        return false
    }

    func cancel() {
        sequence = nil
    }

    private func finish(at time: TimeInterval) -> Bool {
        guard let current = sequence else { return false }
        sequence = nil

        let elapsed = max(0, time - current.startedAt)
        return current.reachedRequiredCount &&
            current.maximumContactCount == configuration.fingerCount &&
            !current.invalid &&
            !current.consumedByMouseClick &&
            elapsed <= configuration.maximumDuration
    }
}
