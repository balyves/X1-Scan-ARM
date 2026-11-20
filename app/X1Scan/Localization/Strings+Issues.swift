// SPDX-License-Identifier: MIT
import Foundation
import X1ScanCore

/// The texts of the error messages (lot A, step B): `issue.<id>.title`,
/// `.cause` and `.step1` to `.step3` in the String Catalog, in English and
/// French (a test checks every identifier).
extension Strings {
    struct IssueTexts: Equatable {
        var title: String
        var cause: String
        var steps: [String]
    }

    static func issueTexts(_ issue: UserIssue) -> IssueTexts {
        let id = issue.id.rawValue
        // The window's power-cycle step first; the case's own then left out (one such step).
        let steps = (1...IssueID.maximumSteps).compactMap { number -> String? in
            if !issue.extraSteps.isEmpty, number == issue.id.powerCycleStep { return nil }
            return issueString("issue.\(id).step\(number)")
        }
        return IssueTexts(title: issueString("issue.\(id).title") ?? issueString("issue.unknown.title") ?? id,
                          cause: issueString("issue.\(id).cause") ?? "",
                          steps: issue.extraSteps + steps)
    }

    static var issueWhatToDo: String {
        String(localized: "issue.whatToDo", defaultValue: "What to do", comment: "Error message: heading above the steps to follow")
    }
    static var issueDetails: String {
        String(localized: "issue.details", defaultValue: "Details", comment: "Error message: folded part with the technical text")
    }
    static var issueCopyDetails: String {
        String(localized: "issue.copyDetails", defaultValue: "Copy Details", comment: "Error message: button that copies the technical details for a bug report")
    }
    static var issueHelp: String {
        String(localized: "issue.help", defaultValue: "Help", comment: "Error message: button that opens its Troubleshooting entry in the help")
    }
    static var issueHelpTooltip: String {
        String(localized: "issue.help.tooltip", defaultValue: "Open the Troubleshooting entry for this message", comment: "Tooltip of an error message's Help button")
    }

    /// The advice after a run on the real X1 stopped before SCAN, or a stop sequence that failed.
    static var powerCycleBeforeAnything: String {
        String(localized: "Switch the X1 off and on again before anything else.",
               comment: "Step of an error message: after a preview or scan on the real X1 stopped before SCAN, or a stop sequence that failed")
    }

    /// For Copy Details: the identifier, the title and the technical text, in
    /// one block for a bug report.
    static func issueReport(_ issue: UserIssue) -> String {
        let context = issue.context.map { "\($0)\n" } ?? ""
        return "X1 Scan — \(issue.id.rawValue)\n\(context)\(issueTexts(issue).title)\n\n\(issue.details)"
    }

    /// Nil when the catalog has no such key (the lookup gives the key back).
    private static func issueString(_ key: String) -> String? {
        let value = Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
        return value == key ? nil : value
    }
}
