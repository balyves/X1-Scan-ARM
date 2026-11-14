// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// Folder, file name and format of the export.
struct ExportPaletteView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folder", comment: "Export palette label").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(model.exportSettings.folder?.path(percentEncoded: false)
                     ?? String(localized: "None", comment: "No export folder chosen"))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(model.exportSettings.folder?.path(percentEncoded: false) ?? "")
                Spacer()
                Button(String(localized: "Choose…", comment: "Button")) {
                    ExportFolderPanel.choose(for: NSApp.keyWindow, model: model)
                }
            }
            .font(.callout)

            Text("File name", comment: "Export palette label").font(.caption).foregroundStyle(.secondary)
            TextField(String(localized: "File name", comment: "Export palette label"),
                      text: $model.exportSettings.nameTemplate)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
            Text(ExportNameHelp.tokens)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ExportNameHelp.next(model))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Format", comment: "Export palette label").font(.caption).foregroundStyle(.secondary)
            Text("TIFF, 16-bit RGB, linear, raw: no profile, no curve.", comment: "Export format")
                .font(.callout)

            Button(String(localized: "Export", comment: "Palette title")) { model.export() }
                .disabled(!model.toolbar.canExport)

            switch model.lastExport {
            case .success(let url):
                HStack {
                    Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Button(String(localized: "Show in Finder", comment: "Button")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            case .failure(let error):
                Text(Strings.exportError(error)).font(.caption).foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
    }
}
