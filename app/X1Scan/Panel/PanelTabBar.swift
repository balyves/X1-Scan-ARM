// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// The tab bar at the top of the settings panel (lot 1b): a native
/// segmented control across the panel's width, one segment per visible tab
/// (`PanelTab.visible`), each with its tooltip (a SwiftUI segmented
/// picker cannot give a segment its own tooltip).
struct PanelTabBar: NSViewRepresentable {
    @Binding var selection: PanelTab

    func makeNSView(context: Context) -> NSSegmentedControl {
        let tabs = PanelTab.visible
        let control = NSSegmentedControl(labels: tabs.map(Strings.panelTab), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        // A tab bar, not a row: regular size, like the Preview and Scan buttons (large) below.
        control.controlSize = .regular
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for (index, tab) in tabs.enumerated() {
            let help = Strings.panelTabHelp(tab)
            control.setToolTip(Strings.panelTabShortcut(tab).map { Strings.withShortcut(help, $0) } ?? help, forSegment: index)
        }
        control.setAccessibilityLabel(Strings.panelTabsLabel)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = PanelTab.visible.firstIndex(of: selection) ?? 0
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<PanelTab>

        init(selection: Binding<PanelTab>) { self.selection = selection }

        @objc func changed(_ sender: NSSegmentedControl) {
            let tabs = PanelTab.visible
            guard tabs.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = tabs[sender.selectedSegment]
        }
    }
}
