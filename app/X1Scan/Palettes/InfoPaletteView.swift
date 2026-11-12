// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Values under the pointer: corrected 16-bit values (as exported) in large,
/// raw CCD samples in small below.
struct InfoPaletteView: View {
    @Bindable var model: AppModel

    var body: some View {
        let reading = model.pixelReading
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Text(verbatim: "x \(reading.map { String($0.coordinate.x) } ?? "–")")
                Text(verbatim: "y \(reading.map { String($0.coordinate.y) } ?? "–")")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)

            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    channelHeader("R", .red)
                    channelHeader("G", .green)
                    channelHeader("B", .blue)
                }
                GridRow {
                    ForEach(0..<3, id: \.self) { channel in
                        value(reading?.corrected[channel]).font(.title3.monospacedDigit())
                    }
                }
                GridRow {
                    ForEach(0..<3, id: \.self) { channel in
                        value(reading?.raw[channel]).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Large: corrected values (exported). Small: raw sensor values.", comment: "Info palette legend")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func channelHeader(_ name: String, _ color: Color) -> some View {
        Text(verbatim: name).font(.caption.weight(.semibold)).foregroundStyle(color)
            .frame(minWidth: 56, alignment: .trailing)
    }

    private func value(_ value: UInt16?) -> Text {
        value.map { Text(verbatim: String($0)) } ?? Text(verbatim: "–")
    }
}
