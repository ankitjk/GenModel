//
//  ExportView.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import SwiftUI

struct ExportView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var exportError: String?
    @State private var showError = false
    @State private var exportSuccess = false

    private var modelFormat: String {
        appModel.generatedModelURL?.pathExtension.uppercased() ?? "Unknown"
    }

    private var formatDescription: String {
        switch appModel.generatedModelURL?.pathExtension.lowercased() {
        case "glb", "gltf":
            return "GLB (Universal)"
        case "obj":
            return "OBJ (Wavefront)"
        case "ply":
            return "PLY (Point Cloud)"
        case "usdz":
            return "USDZ (Apple)"
        default:
            return "3D Model"
        }
    }

    private var formatSubtitle: String {
        switch appModel.generatedModelURL?.pathExtension.lowercased() {
        case "glb", "gltf":
            return "Compatible with most 3D viewers and editors"
        case "obj":
            return "Compatible with most 3D software"
        case "ply":
            return "Point cloud format, limited viewer support"
        case "usdz":
            return "Optimized for Apple devices"
        default:
            return "3D model file"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if exportSuccess {
                    // Success state
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)

                    Text("Model Saved!")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Your \(modelFormat) model has been saved to the app's Documents folder.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("File: model.\(modelFormat.lowercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("You can access it via Files app > On My Device > GenModel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                } else {
                    // Export options state
                    Text("Export 3D Model")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Your model will be exported in \(modelFormat) format")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "cube.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatDescription)
                                    .font(.headline)

                                Text(formatSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title2)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    Button {
                        saveToDocuments()
                    } label: {
                        Label("Save to Documents", systemImage: "folder.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.generatedModelData == nil)
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
        }
    }

    private func saveToDocuments() {
        guard let modelData = appModel.generatedModelData else {
            exportError = "No model data available"
            showError = true
            return
        }

        print("Saving export with \(modelData.count) bytes")

        let ext = appModel.generatedModelURL?.pathExtension.lowercased() ?? "glb"
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent("model").appendingPathExtension(ext)

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try modelData.write(to: fileURL)
            print("Saved file to: \(fileURL.path)")
            exportSuccess = true
        } catch {
            print("Failed to save file: \(error)")
            exportError = "Failed to save file: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    ExportView()
        .environment(AppModel())
}
