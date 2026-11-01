import Foundation

/// UserDefaults keys and defaults for user-editable settings. Views bind to
/// these with `@AppStorage(AppSettings.Keys.…)`; services read `TimesheetSettings.current`.
enum AppSettings {
    enum Keys {
        static let signerName = "timesheet.signerName"
        static let organization = "timesheet.organization"
        static let includeSupervisorSignature = "timesheet.includeSupervisorSignature"
        /// Monthly hours goal shown on the dashboard; 0 = no target.
        static let monthlyTargetHours = "goal.monthlyTargetHours"
        /// The project used most recently, pre-selected for new entries and the timer.
        static let lastProjectID = "entry.lastProjectID"
        /// Signature used automatically on export; empty = ask every time.
        static let defaultSignatureID = "signature.defaultID"
    }

    enum Defaults {
        static let signerName = ""
        static let organization = ""
        static let includeSupervisorSignature = true
        static let monthlyTargetHours = 0.0
        static let lastProjectID = ""
        static let defaultSignatureID = ""
    }
}

/// What the monthly PDF timesheet prints in its header and signature block.
struct TimesheetSettings {
    var signerName: String
    var organization: String
    var includeSupervisorSignature: Bool

    static var current: TimesheetSettings {
        let defaults = UserDefaults.standard
        return TimesheetSettings(
            signerName: (defaults.string(forKey: AppSettings.Keys.signerName) ?? AppSettings.Defaults.signerName)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            organization: (defaults.string(forKey: AppSettings.Keys.organization) ?? AppSettings.Defaults.organization)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            includeSupervisorSignature: defaults.object(forKey: AppSettings.Keys.includeSupervisorSignature) as? Bool
                ?? AppSettings.Defaults.includeSupervisorSignature
        )
    }
}
