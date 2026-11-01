import Foundation

/// UserDefaults keys and defaults for user-editable settings. Views bind to
/// these with `@AppStorage(AppSettings.Keys.…)`; services read `TimesheetSettings.current`.
enum AppSettings {
    enum Keys {
        static let signerName = "timesheet.signerName"
        static let organization = "timesheet.organization"
        static let includeSupervisorSignature = "timesheet.includeSupervisorSignature"
    }

    enum Defaults {
        static let signerName = ""
        static let organization = ""
        static let includeSupervisorSignature = true
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
