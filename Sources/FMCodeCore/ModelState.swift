import FoundationModels

public enum ModelState: Equatable, Sendable {
    case available, deviceNotEligible, appleIntelligenceOff, notReady, other(String)

    public static var current: ModelState {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(let reason): ModelState(reason)
        }
    }

    init(_ reason: SystemLanguageModel.Availability.UnavailableReason) {
        switch reason {
        case .deviceNotEligible: self = .deviceNotEligible
        case .appleIntelligenceNotEnabled: self = .appleIntelligenceOff
        case .modelNotReady: self = .notReady
        @unknown default: self = .other(String(describing: reason))
        }
    }

    /// Human-readable reason plus the fix.
    public var explanation: String {
        switch self {
        case .available: "available"
        case .deviceNotEligible: "this Mac isn't eligible for Apple Intelligence (Apple Silicon required)"
        case .appleIntelligenceOff: "Apple Intelligence is off — enable it in System Settings › Apple Intelligence & Siri"
        case .notReady: "the model is still downloading — try again in a few minutes"
        case .other(let why): why
        }
    }
}
