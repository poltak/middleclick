import Foundation
import Testing
@testable import MiddleClick

@Suite("Three-finger gesture recognition")
struct GestureRecognizerTests {
    @Test func staggeredThreeFingerTapIsRecognized() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [contact(1)])))
        #expect(!recognizer.process(frame(0.03, [contact(1), contact(2)])))
        #expect(!recognizer.process(frame(0.06, [contact(1), contact(2), contact(3)])))
        #expect(recognizer.process(frame(0.14, [])))
    }

    @Test func swipeIsNotRecognizedAsTap() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.08, contacts(atX: 0.3))))
        #expect(!recognizer.process(frame(0.12, [])))
    }

    @Test func fourFingerSequenceIsRejected() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.04, [
            contact(1), contact(2), contact(3), contact(4),
        ])))
        #expect(!recognizer.process(frame(0.10, [])))
    }

    @Test func fingerIdentityChangesDoNotRejectTap() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.04, [contact(2), contact(3), contact(4)])))
        #expect(recognizer.process(frame(0.10, [])))
    }

    @Test func stationaryCentroidPinchIsRejected() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [
            contact(1, x: 0.1), contact(2, x: 0.2), contact(3, x: 0.3),
        ])))
        #expect(!recognizer.process(frame(0.05, [
            contact(1, x: 0.16), contact(2, x: 0.2), contact(3, x: 0.24),
        ])))
        #expect(!recognizer.process(frame(0.10, [])))
    }

    @Test func movementDuringStaggeredLiftoffIsRejected() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.05, [
            contact(1, x: 0.2), contact(2, x: 0.3),
        ])))
        #expect(!recognizer.process(frame(0.10, [])))
    }

    @Test func physicalClickConsumesTapSequence() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(recognizer.claimPhysicalClick())
        #expect(!recognizer.process(frame(0.10, [])))
    }

    @Test func tapCanRemainDownPastFingerArrivalWindow() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.20, contacts(atX: 0.2))))
        #expect(recognizer.process(frame(0.25, [])))
    }

    @Test func physicalClickCanBeClaimedAfterLongHoldAndMovement() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(1.00, contacts(atX: 0.4))))
        #expect(recognizer.claimPhysicalClick())
        #expect(!recognizer.process(frame(1.10, [])))
    }

    @Test func staggeredArrivalAndLiftoffAreRecognized() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [contact(1)])))
        #expect(!recognizer.process(frame(0.20, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.28, [contact(2), contact(3)])))
        #expect(!recognizer.process(frame(0.32, [contact(3)])))
        #expect(recognizer.process(frame(0.36, [])))
    }

    @Test func sequenceLongerThanTapLimitIsRejected() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [contact(1)])))
        #expect(!recognizer.process(frame(0.30, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.50, [])))
    }

    @Test func twoIndependentTapsAreBothRecognized() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(recognizer.process(frame(0.08, [])))
        #expect(!recognizer.process(frame(0.10, contacts(atX: 0.2))))
        #expect(recognizer.process(frame(0.18, [])))
    }

    private func frame(_ time: TimeInterval, _ contacts: [TouchContact]) -> TouchFrame {
        TouchFrame(time: time, contacts: contacts)
    }

    private func contact(_ id: Int32, x: Float = 0.2, y: Float = 0.2) -> TouchContact {
        TouchContact(id: id, position: .init(x, y))
    }

    private func contacts(atX x: Float) -> [TouchContact] {
        [contact(1, x: x), contact(2, x: x), contact(3, x: x)]
    }
}

@Suite("Pending tap coordination")
struct PendingTapCoordinatorTests {
    @Test func rapidTapsAreDeliveredIndependently() {
        var coordinator = PendingTapCoordinator()
        let first = coordinator.schedule(at: 0.08, delay: 0.12)
        let second = coordinator.schedule(at: 0.18, delay: 0.12)

        let firedFirst = coordinator.fire(id: first)
        let firedSecond = coordinator.fire(id: second)
        #expect(firedFirst)
        #expect(firedSecond)
    }

    @Test func nativeClicksConsumeOnePendingTap() {
        var coordinator = PendingTapCoordinator()
        let first = coordinator.schedule(at: 0.08, delay: 0.12)
        let second = coordinator.schedule(at: 0.18, delay: 0.12)

        let claimed = coordinator.claim(at: 0.19)
        let firedFirst = coordinator.fire(id: first)
        let firedSecond = coordinator.fire(id: second)
        #expect(claimed)
        #expect(!firedFirst)
        #expect(firedSecond)
    }
}

@Suite("Raw touch contact adaptation")
struct TouchContactAdapterTests {
    @Test func includesOnlyMakeTouchAndTouchingStates() {
        #expect(!TouchContactAdapter.isTouching(state: 0))
        #expect(!TouchContactAdapter.isTouching(state: 1))
        #expect(!TouchContactAdapter.isTouching(state: 2))
        #expect(TouchContactAdapter.isTouching(state: 3))
        #expect(TouchContactAdapter.isTouching(state: 4))
        #expect(!TouchContactAdapter.isTouching(state: 5))
        #expect(!TouchContactAdapter.isTouching(state: 6))
        #expect(!TouchContactAdapter.isTouching(state: 7))
    }
}
