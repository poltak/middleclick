import CoreFoundation
import Foundation

enum SystemSettings {
    enum GestureConflict: Equatable {
        case threeFingerDrag
        case threeFingerLookUp
    }

    private static let trackpadDomains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]

    static var threeFingerDragEnabled: Bool {
        numericTrackpadPreference("TrackpadThreeFingerDrag") != 0
    }

    static var threeFingerLookUpEnabled: Bool {
        numericTrackpadPreference("TrackpadThreeFingerTapGesture") != 0
    }

    static var gestureConflict: GestureConflict? {
        if threeFingerDragEnabled { return .threeFingerDrag }
        if threeFingerLookUpEnabled { return .threeFingerLookUp }
        return nil
    }

    private static func numericTrackpadPreference(_ key: String) -> Int {
        for domain in trackpadDomains {
            _ = CFPreferencesAppSynchronize(domain as CFString)
            guard let value = CFPreferencesCopyAppValue(
                key as CFString,
                domain as CFString
            ) as? NSNumber else { continue }
            if value.intValue != 0 { return value.intValue }
        }
        return 0
    }
}
