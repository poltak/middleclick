import Foundation
import Testing
@testable import MiddleClick

@Suite("Three-finger edge outlier guard")
struct EdgeOutlierGestureTests {
    @Test func recordedEdgeOutlierSequenceIsRejected() {
        let recognizer = ThreeFingerGestureRecognizer()
        let upper = contact(3, x: 0.7837, y: 0.7269)
        let lower = contact(2, x: 0.6396, y: 0.8065)
        let edge = contact(10, x: 1.0, y: 0.0449)

        #expect(!recognizer.process(frame(0.000, [upper, edge])))
        #expect(!recognizer.process(frame(0.008, [lower, upper, edge])))
        #expect(!recognizer.process(frame(0.248, [lower, upper, edge])))
        #expect(!recognizer.process(frame(0.256, [upper])))
        #expect(!recognizer.process(frame(0.264, [])))
    }

    @Test func nearbyContactsAtTheEdgeAreAccepted() {
        let contacts = [
            contact(1, x: 0.002, y: 0.50),
            contact(2, x: 0.030, y: 0.50),
            contact(3, x: 0.050, y: 0.51),
        ]

        #expect(completesTap(with: contacts))
    }

    @Test func widelySpreadInteriorContactsAreAccepted() {
        let contacts = [
            contact(1, x: 0.20, y: 0.20),
            contact(2, x: 0.80, y: 0.20),
            contact(3, x: 0.50, y: 0.80),
        ]

        #expect(completesTap(with: contacts))
    }

    @Test func boundaryAloneDoesNotRejectTap() {
        let contacts = [
            contact(1, x: 0.005, y: 0.50),
            contact(2, x: 0.080, y: 0.50),
            contact(3, x: 0.120, y: 0.50),
        ]

        #expect(completesTap(with: contacts))
    }

    @Test func distanceAloneDoesNotRejectInteriorTap() {
        let contacts = [
            contact(1, x: 0.25, y: 0.50),
            contact(2, x: 0.50, y: 0.50),
            contact(3, x: 0.875, y: 0.50),
        ]

        #expect(completesTap(with: contacts))
    }

    @Test func guardUsesStrictDistanceAndInclusiveBoundaryLimits() {
        let configuration = GestureConfiguration(
            edgeOutlierDistanceThreshold: 0.25,
            edgeBoundaryBand: 0.125
        )
        let atDistanceLimit = [
            contact(1, x: 0.50, y: 0.50),
            contact(2, x: 0.625, y: 0.50),
            contact(3, x: 0.875, y: 0.50),
        ]
        let atBoundaryLimit = [
            contact(1, x: 0.25, y: 0.50),
            contact(2, x: 0.50, y: 0.50),
            contact(3, x: 0.875, y: 0.50),
        ]

        #expect(completesTap(with: atDistanceLimit, configuration: configuration))
        #expect(!completesTap(with: atBoundaryLimit, configuration: configuration))
    }

    @Test func tiedClosestPairsDoNotCreateOrderDependentEdgeOutlier() {
        let contacts = [
            contact(1, x: 1.00, y: 0.50),
            contact(2, x: 0.50, y: 0.50),
            contact(3, x: 0.25, y: 0.9330127),
        ]
        let orders = [
            [0, 1, 2], [0, 2, 1], [1, 0, 2],
            [1, 2, 0], [2, 0, 1], [2, 1, 0],
        ]

        for order in orders {
            #expect(completesTap(with: order.map { contacts[$0] }))
        }
    }

    @Test func outlierMovingInsideBoundaryDoesNotRestoreSequence() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [
            contact(1, x: 0.30),
            contact(2, x: 0.40),
            contact(3, x: 1.00),
        ])))
        #expect(!recognizer.process(frame(0.04, [
            contact(1, x: 0.30),
            contact(2, x: 0.40),
            contact(3, x: 0.989),
        ])))
        #expect(!recognizer.process(frame(0.10, [])))
    }

    @Test func fourContactsDoNotBecomeAThreeFingerTapAfterOneLifts() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [contact(1), contact(2), contact(3)])))
        #expect(!recognizer.process(frame(0.04, [
            contact(1), contact(2), contact(3), contact(4, x: 1.00, y: 0.50),
        ])))
        #expect(!recognizer.process(frame(0.08, [contact(1), contact(2), contact(3)])))
        #expect(!recognizer.process(frame(0.12, [])))
    }

    @Test func edgeOutlierSequenceCanStillBeClaimedByPhysicalClick() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [
            contact(1, x: 0.30),
            contact(2, x: 0.40),
            contact(3, x: 1.00),
        ])))
        #expect(recognizer.claimPhysicalClick())
        #expect(!recognizer.process(frame(0.10, [])))
    }

    @Test func normalTapWorksAfterRejectedOutlierSequence() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [
            contact(1, x: 0.30),
            contact(2, x: 0.40),
            contact(3, x: 1.00),
        ])))
        #expect(!recognizer.process(frame(0.10, [])))
        #expect(!recognizer.process(frame(0.20, [contact(1), contact(2), contact(3)])))
        #expect(recognizer.process(frame(0.30, [])))
    }

    @Test func recordedOutlierIsRejectedForEveryContactOrder() {
        let contacts = [
            contact(3, x: 0.7837, y: 0.7269),
            contact(2, x: 0.6396, y: 0.8065),
            contact(10, x: 1.0, y: 0.0449),
        ]
        let orders = [
            [0, 1, 2], [0, 2, 1], [1, 0, 2],
            [1, 2, 0], [2, 0, 1], [2, 1, 0],
        ]

        for order in orders {
            let recognizer = ThreeFingerGestureRecognizer()
            let orderedContacts = order.map { contacts[$0] }

            #expect(!recognizer.process(frame(0.000, [contacts[0], contacts[2]])))
            #expect(!recognizer.process(frame(0.008, orderedContacts)))
            #expect(!recognizer.process(frame(0.248, orderedContacts)))
            #expect(!recognizer.process(frame(0.256, [contacts[0]])))
            #expect(!recognizer.process(frame(0.264, [])))
        }
    }

    private func completesTap(
        with contacts: [TouchContact],
        configuration: GestureConfiguration = .init()
    ) -> Bool {
        let recognizer = ThreeFingerGestureRecognizer(configuration: configuration)
        _ = recognizer.process(frame(0.00, contacts))
        return recognizer.process(frame(0.10, []))
    }

    private func frame(_ time: TimeInterval, _ contacts: [TouchContact]) -> TouchFrame {
        TouchFrame(time: time, contacts: contacts)
    }

    private func contact(
        _ id: Int32,
        x: Float = 0.20,
        y: Float = 0.20
    ) -> TouchContact {
        TouchContact(id: id, position: .init(x, y))
    }
}
