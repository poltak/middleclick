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
    var maximumDuration: TimeInterval = 0.45
    var maximumMovement: Float = 0.05
}

/// Recognizes one complete gesture on one physical multitouch device.
final class ThreeFingerGestureRecognizer: @unchecked Sendable {
    private struct Sequence: Sendable {
        let startedAt: TimeInterval
        var currentContactCount: Int
        var reachedRequiredCount = false
        var maximumContactCount: Int
        var referencePositions: [SIMD2<Float>]?
        var tapInvalid = false
        var sawExtraFinger = false
        var consumedByMouseClick = false
    }

    private let configuration: GestureConfiguration
    private var sequence: Sequence?

    init(configuration: GestureConfiguration = .init()) {
        self.configuration = configuration
    }

    var hasClaimablePhysicalClick: Bool {
        guard let sequence else { return false }
        return !sequence.consumedByMouseClick &&
            !sequence.sawExtraFinger &&
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
                currentContactCount: frame.contacts.count,
                maximumContactCount: frame.contacts.count,
                referencePositions: nil
            )
        }

        guard var current = sequence else { return false }
        current.currentContactCount = frame.contacts.count
        current.maximumContactCount = max(current.maximumContactCount, frame.contacts.count)

        let elapsed = max(0, frame.time - current.startedAt)
        if elapsed > configuration.maximumDuration {
            current.tapInvalid = true
        }
        if current.maximumContactCount > configuration.fingerCount {
            current.tapInvalid = true
            current.sawExtraFinger = true
        }

        if let referencePositions = current.referencePositions {
            let positions = frame.contacts.map(\.position)
            if minimumMaximumDistance(from: positions, to: referencePositions) >
                configuration.maximumMovement
            {
                current.tapInvalid = true
            }
        } else if frame.contacts.count == configuration.fingerCount {
            current.referencePositions = frame.contacts.map(\.position)
            current.reachedRequiredCount = true
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
            !current.tapInvalid &&
            !current.consumedByMouseClick &&
            elapsed <= configuration.maximumDuration
    }

    /// Finds the best identity-independent assignment of current contacts to
    /// their original positions. Contact IDs can change while fingers lift.
    private func minimumMaximumDistance(
        from positions: [SIMD2<Float>],
        to references: [SIMD2<Float>]
    ) -> Float {
        guard !positions.isEmpty else { return 0 }
        var best = Float.infinity

        func search(_ index: Int, _ available: [Int], _ maximum: Float) {
            guard maximum < best else { return }
            if index == positions.count {
                best = maximum
                return
            }
            for referenceIndex in available {
                let distance = simd_distance(positions[index], references[referenceIndex])
                search(
                    index + 1,
                    available.filter { $0 != referenceIndex },
                    max(maximum, distance)
                )
            }
        }

        search(0, Array(references.indices), 0)
        return best
    }
}
