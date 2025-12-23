//
//  ExportView.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportFormat = .usdz
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showError = false
    @State private var exportData: Data?
    @State private var showFileExporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Export 3D Model")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Choose a format to export your generated model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ExportFormat.allCases) { format in
                        ExportFormatRow(
                            format: format,
                            isSelected: selectedFormat == format
                        ) {
                            selectedFormat = format
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                if isExporting {
                    ProgressView("Preparing export...")
                } else {
                    Button {
                        prepareExport()
                    } label: {
                        Label("Export to Files", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.modelURLs == nil)
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Export Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "Unknown error")
            }
            .fileExporter(
                isPresented: $showFileExporter,
                document: ExportDocument(data: exportData ?? Data()),
                contentType: utType(for: selectedFormat),
                defaultFilename: "model.\(selectedFormat.fileExtension)"
            ) { result in
                switch result {
                case .success(let url):
                    print("Exported to: \(url)")
                    dismiss()
                case .failure(let error):
                    exportError = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func prepareExport() {
        guard let modelURLs = appModel.modelURLs else {
            exportError = "No model URLs available"
            showError = true
            return
        }

        let urlString: String?
        switch selectedFormat {
        case .usdz:
            urlString = modelURLs.usdz
        case .glb:
            urlString = modelURLs.glb
        case .obj:
            urlString = modelURLs.obj
        }

        guard let urlString = urlString else {
            exportError = "This format is not available for this model"
            showError = true
            return
        }

        isExporting = true

        Task {
            do {
                let data = try await appModel.apiClient.downloadModel(from: urlString)
                await MainActor.run {
                    exportData = data
                    isExporting = false
                    showFileExporter = true
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                    showError = true
                }
            }
        }
    }

    private func utType(for format: ExportFormat) -> UTType {
        switch format {
        case .usdz:
            return .usdz
        case .glb:
            return UTType(filenameExtension: "glb") ?? .data
        case .obj:
            return UTType(filenameExtension: "obj") ?? .plainText
        }
    }
}

struct ExportFormatRow: View {
    let format: ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(format.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(formatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var formatDescription: String {
        switch format {
        case .usdz:
            return "Best for Apple devices (visionOS, iOS, macOS)"
        case .glb:
            return "Universal format for web and cross-platform"
        case .obj:
            return "Compatible with 3D modeling software"
        }
    }
}

// MARK: - Export Document

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.usdz, .data]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ExportView()
        .environment(AppModel())
}
