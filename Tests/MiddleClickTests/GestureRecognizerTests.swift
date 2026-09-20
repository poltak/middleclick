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

    @Test func fourDistinctFingersAcrossFramesAreRejected() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.04, [contact(2), contact(3), contact(4)])))
        #expect(!recognizer.process(frame(0.10, [])))
    }

    @Test func physicalClickConsumesTapSequence() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, contacts(atX: 0.2))))
        #expect(recognizer.claimPhysicalClick())
        #expect(!recognizer.process(frame(0.10, [])))
    }

    @Test func lateThirdFingerIsRejected() {
        let recognizer = ThreeFingerGestureRecognizer()

        #expect(!recognizer.process(frame(0.00, [contact(1)])))
        #expect(!recognizer.process(frame(0.20, contacts(atX: 0.2))))
        #expect(!recognizer.process(frame(0.25, [])))
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
