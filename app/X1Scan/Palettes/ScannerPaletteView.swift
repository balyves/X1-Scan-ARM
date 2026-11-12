// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Source, state, identity and usage counters.
struct ScannerPaletteView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(String(localized: "Source", comment: "Scanner palette label"), selection: $model.source) {
                ForEach(ScannerSourceKind.allCases, id: \.self) { source in
                    Text(Strings.source(source)).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.session.isBusy)

            if model.source == .real { realScannerSection }
            if model.source == .virtual, let error = model.virtualScannerError {
                Label(String(localized: "The virtual X1 could not be loaded.", comment: "Why Preview is disabled"),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                row(String(localized: "State", comment: "Scanner palette label"), stateText)
                if let info = model.scannerInfo {
                    row(String(localized: "Model", comment: "Scanner palette label"), "\(info.vendor) \(info.model)")
                    row(String(localized: "Firmware", comment: "Scanner palette label"), info.firmware)
                    if let serial = info.serialNumber { serialRow(serial) }
                }
            }
            .font(.callout)

            if let info = model.scannerInfo, !info.counters.isEmpty { counters(info.counters) }
        }
    }

    private var stateText: String {
        if model.source == .virtual, model.session.isBusy {
            return String(localized: "Preview in progress", comment: "Scanner state")
        }
        if model.source == .real, model.realStatus == .notRead {
            return String(localized: "Not read", comment: "Scanner state")
        }
        return Strings.scannerState(model.scannerInfo?.state)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func serialRow(_ serial: String) -> some View {
        GridRow {
            Text("Serial No.", comment: "Scanner palette label").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(SerialMasking.display(serial, revealed: model.serialRevealed))
                    .monospaced()
                    .textSelection(.enabled)
                Button {
                    model.serialRevealed.toggle()
                } label: {
                    Image(systemName: model.serialRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(model.serialRevealed ? Text("Hide the serial number", comment: "Tooltip")
                                           : Text("Show the serial number", comment: "Tooltip"))
            }
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
            HStack {
                Button(String(localized: "Read Scanner", comment: "Button")) {
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
            }
            Text(Strings.previewBlock(.realScannerReadOnly))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    private func counters(_ counters: [UInt32]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage counters (log page 0x30)", comment: "Scanner palette section")
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
