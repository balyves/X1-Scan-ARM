// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// A message that says what to do (lot A, step B): a short title (what
/// happened), the likely cause in one sentence, one to three steps, a Help
/// button that opens the Troubleshooting entry of the same identifier, and
/// the technical text of before in a folded Details part, to copy into a
/// bug report.
struct IssueView: View {
    let issue: UserIssue
    /// Inline (Scanner Information): no title icon, no OK button.
    var inline = false
    /// Buttons beside Help: the sheet's OK, and extra actions (Try Without a Scanner).
    var actions: [IssueAction] = []
    var help: () -> Void
    /// Esc: the sheet's OK.
    var close: (() -> Void)?
    @State private var detailsShown = false

    init(issue: UserIssue, inline: Bool = false, actions: [IssueAction] = [], detailsShown: Bool = false,
         help: @escaping () -> Void, close: (() -> Void)? = nil) {
        self.issue = issue
        self.inline = inline
        self.actions = actions
        self.help = help
        self.close = close
        _detailsShown = State(initialValue: detailsShown)
    }

    var body: some View {
        let texts = Strings.issueTexts(issue)
        VStack(alignment: .leading, spacing: 10) {
            if let context = issue.context {
                Text(context).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                if !inline {
                    Image(systemName: issue.id.isSafetyStop ? "exclamationmark.shield" : "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(texts.title)
                        .font(inline ? .callout.weight(.semibold) : .headline)
                        .foregroundStyle(inline ? Color(nsColor: .systemRed) : Color.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(texts.cause)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if !texts.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Strings.issueWhatToDo)
                                .font(.callout.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(texts.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(verbatim: "\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                                    Text(step).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.callout)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            DisclosureGroup(isExpanded: $detailsShown) {
                VStack(alignment: .trailing, spacing: 4) {
                    ScrollView {
                        Text(issue.details)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 110)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    Button(Strings.issueCopyDetails) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Strings.issueReport(issue), forType: .string)
                    }
                    .controlSize(.small)
                }
            } label: {
                Text(Strings.issueDetails)
                    .font(.callout)
            }
            HStack {
                Button(Strings.issueHelp) { help() }
                    .help(Strings.issueHelpTooltip)
                Spacer()
                ForEach(actions) { action in
                    Button(action.title, action: action.perform)
                        .keyboardShortcut(action.isDefault ? .defaultAction : nil)
                }
            }
        }
        .padding(inline ? 0 : 20)
        .frame(width: inline ? nil : 460, alignment: .leading)
        .background {
            // Esc closes the sheet, as Cancel would (the visible default button is OK).
            if let close {
                Button("", action: close)
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct IssueAction: Identifiable {
    let id = UUID()
    let title: String
    var isDefault = false
    let perform: () -> Void
}

/// Shows an `IssueView` as a sheet of the main window. Several messages in
/// a row wait for each other, as NSAlert sheets did.
@MainActor
enum IssueSheet {
    /// `extra`: actions beside OK (each closes the sheet first).
    static func present(_ issue: UserIssue, on window: NSWindow, extra: [(String, @MainActor () -> Void)] = []) {
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let close: @MainActor () -> Void = { [weak window, weak sheet] in
            if let sheet { window?.endSheet(sheet) }
        }
        var actions = extra.map { title, perform in
            IssueAction(title: title) {
                close()
                perform()
            }
        }
        actions.append(IssueAction(title: String(localized: "OK", comment: "Button"), isDefault: true) { close() })
        let view = IssueView(issue: issue, actions: actions, help: {
            (NSApp.delegate as? AppDelegate)?.showHelp(page: IssueID.helpPage, anchor: issue.id.helpAnchor)
        }, close: close)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        sheet.contentViewController = hosting
        sheet.title = Strings.issueTexts(issue).title  // read by VoiceOver
        window.beginSheet(sheet)
    }
}
