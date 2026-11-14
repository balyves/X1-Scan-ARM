// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// Scanner > Scanner Information… (⌘I): identity, state and usage counters
/// of the current source. Shows the last reading; it never reads by itself.
@MainActor
final class ScannerInfoWindowController: NSWindowController {
    init(model: AppModel) {
        let hosting = NSHostingController(rootView: ScannerInfoView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Scanner Information", comment: "Window title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setFrameAutosaveName("ScannerInformation")
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// Source, state, identity and usage counters.
struct ScannerInfoView: View {
    @Bindable var model: AppModel
    /// Debug snapshots mask the serial whatever the setting.
    var alwaysMasksSerial = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.source(model.source)).font(.title3.weight(.semibold))

            if model.source == .real { realScannerSection }
            if model.source == .virtual, let error = model.virtualScannerError {
                Label(String(localized: "The virtual X1 could not be loaded.", comment: "Why Preview is disabled"),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                row(String(localized: "State", comment: "Scanner information label"), stateText)
                if let info = model.scannerInfo {
                    row(String(localized: "Model", comment: "Scanner information label"), "\(info.vendor) \(info.model)")
                    row(String(localized: "Firmware", comment: "Scanner information label"), info.firmware)
                    if let serial = info.serialNumber {
                        GridRow {
                            Text("Serial No.", comment: "Scanner information label").foregroundStyle(.secondary)
                            Text(alwaysMasksSerial ? SerialMasking.masked(serial) : model.settings.displayedSerial(serial)).monospaced().textSelection(.enabled)
                        }
                    }
                }
            }
            .font(.callout)

            if let info = model.scannerInfo, !info.counters.isEmpty { counters(info.counters) }
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var stateText: String {
        if model.source == .virtual, model.session.isBusy {
            return String(localized: "Preview in progress", comment: "Scanner state")
        }
        if model.source == .real, model.realStatus == .notRead {
            return String(localized: "Not read", comment: "Scanner state")
        }
        if model.source == .real, model.realStatus == .reading {
            return String(localized: "Reading…", comment: "Status: reading the real X1")
        }
        return Strings.scannerState(model.scannerInfo?.state)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var realScannerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Before reading: X1 **on**, FlexColor **closed**.", comment: "Real scanner instructions")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            Text("Only reads are sent (identity, state, counters); the scanner is closed again right after.",
                 comment: "Real scanner instructions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(String(localized: "Read Identity", comment: "Menu item and button")) {
                    Task { await model.readRealScanner() }
                }
                .disabled(model.realStatus == .reading)
                if model.realStatus == .reading { ProgressView().controlSize(.small) }
            }
            if case .failed(let failure) = model.realStatus {
                Text(Strings.inspectorFailure(failure))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Strings.previewBlock(.realScannerReadOnly))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    private func counters(_ counters: [UInt32]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage counters (log page 0x30)", comment: "Scanner information section")
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                ForEach(Array(counters.enumerated()), id: \.offset) { index, value in
                    GridRow {
                        Text("Counter \(index + 1)", comment: "Usage counter label").foregroundStyle(.secondary)
                        Text(value, format: .number).monospacedDigit().gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.callout)
            Text("Meanings not confirmed.", comment: "Note under the usage counters")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
