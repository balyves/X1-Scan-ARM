// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// Help > Check Installation…, the "No X1 found" message's button, and at
/// launch when the adapter or the driver is missing (docs/decisions.md,
/// "Installation check"). The registry is read again every 2 seconds while
/// the window is open (`InstallationMonitor`), read only.
@MainActor
final class InstallationCheckWindowController: NSWindowController, NSWindowDelegate {
    let monitor: InstallationMonitor

    init(monitor: InstallationMonitor = InstallationMonitor()) {
        self.monitor = monitor
        let hosting = NSHostingController(rootView: InstallationCheckView(monitor: monitor))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = Strings.installationTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setFrameAutosaveName("InstallationCheck")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func showWindow(_ sender: Any?) {
        monitor.startWatching()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }

    var isShown: Bool { window?.isVisible ?? false }

    func windowWillClose(_ notification: Notification) {
        monitor.stopWatching()
    }
}

/// One line per element: ✓ or ⚠, its title, what was seen, its help page
/// and, for the driver, its links.
struct InstallationCheckView: View {
    let monitor: InstallationMonitor

    /// ASFireWire, a third-party project (docs/help/*/hardware.md).
    private static let gitHub = URL(string: "https://github.com/mrmidi/ASFireWire")!
    private static let website = URL(string: "https://www.asfw.net/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.installationIntro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if monitor.lines.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Strings.installationReading)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(monitor.lines, id: \.item) { line in
                    row(line)
                }
            }
            Divider()
            Text(Strings.installationLimits)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let checked = monitor.lastChecked {
                    Text(Strings.installationChecked(checked))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(Strings.installationCheckAgain) {
                    Task { await monitor.refresh() }
                }
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
    }

    private func row(_ line: InstallationCheck.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: line.state.isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(line.state.isOK ? Color.green : Color.orange)
                .imageScale(.large)
                .accessibilityHidden(true)  // said with the title
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.installationItem(line.item))
                    .fontWeight(.semibold)
                    .accessibilityLabel(Strings.installationRowAccessibility(line))
                    .accessibilityAddTraits(.isHeader)
                Text(Strings.installationState(line, snapshot: monitor.snapshot))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(Strings.installationHelp) { openHelp(for: line.item) }
                        .buttonStyle(.link)
                        .help(Strings.installationHelpTooltip)
                        .accessibilityLabel(Strings.installationHelpLabel(line.item))
                    if line.item == .driver && !line.state.isOK {
                        Link(Strings.installationGitHub, destination: Self.gitHub)
                        Link(Strings.installationWebsite, destination: Self.website)
                    }
                }
                .font(.callout)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The help page of each line (docs/help/*/hardware.md, troubleshooting.md).
    private func openHelp(for item: InstallationCheck.Item) {
        let target: (page: String, anchor: String?) = switch item {
        case .macOS: ("hardware", nil)
        case .adapter: ("hardware", "chain")
        case .driver: ("hardware", "asfirewire")
        case .scanner: ("troubleshooting", "no-scanner")
        }
        (NSApp.delegate as? AppDelegate)?.showHelp(page: target.page, anchor: target.anchor)
    }
}
