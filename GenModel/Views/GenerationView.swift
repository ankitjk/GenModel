//
//  GenerationView.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import SwiftUI
import RealityKit
import os.log

private let logger = Logger(subsystem: "com.genmodel", category: "GenerationView")

struct GenerationView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showExportSheet = false
    @State private var modelLoadError: String?

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            Group {
                switch appModel.generationPhase {
                case .idle:
                    inputView

                case .generatingPreview, .previewReady, .generatingFinal:
                    GenerationProgressView()

                case .complete:
                    completedView

                case .failed(let error):
                    errorView(error: error)
                }
            }
            .navigationTitle("Generate 3D Model")
            .toolbar {
                if appModel.generationPhase == .complete {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New") {
                            appModel.resetGeneration()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportView()
        }
    }

    // MARK: - Input View

    @ViewBuilder
    private var inputView: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 20) {
            Picker("Input Mode", selection: $appModel.inputMode) {
                Label("Text", systemImage: "text.cursor").tag(AppModel.InputMode.text)
                Label("Image", systemImage: "photo").tag(AppModel.InputMode.image)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch appModel.inputMode {
            case .text:
                TextInputView()
            case .image:
                ImageInputView()
            }
        }
    }

    // MARK: - Completed View

    @ViewBuilder
    private var completedView: some View {
        VStack(spacing: 24) {
            // Model preview section
            modelPreviewSection

            Text("Generation Complete!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your 3D model is ready to view and export.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    showExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)

                ToggleImmersiveSpaceButton()
            }
            .padding(.horizontal)

            Button(role: .destructive) {
                appModel.resetGeneration()
            } label: {
                Label("Generate Another", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Model Preview Section

    @ViewBuilder
    private var modelPreviewSection: some View {
        if let modelURL = appModel.generatedModelURL {
            VStack(spacing: 8) {
                // Show either the 3D preview or an error message
                if modelLoadError != nil {
                    // Show error state instead of RealityView
                    previewErrorView
                } else {
                    // Use RealityView with ModelLoader for multi-format support
                    RealityView { content in
                        logger.info("RealityView make: Loading model from \(modelURL.path)")
                        logger.info("File exists: \(FileManager.default.fileExists(atPath: modelURL.path))")
                        logger.info("File extension: \(modelURL.pathExtension)")

                        do {
                            let entity = try await ModelLoader.loadEntity(from: modelURL)
                            logger.info("Entity loaded successfully via ModelLoader")

                            // Log entity details
                            let bounds = entity.visualBounds(relativeTo: nil)
                            logger.info("Entity bounds: \(bounds.extents)")

                            // Auto-scale to fit in preview
                            let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                            if maxExtent > 0 {
                                let targetSize: Float = 0.15 // Small preview size in meters
                                let scale = targetSize / maxExtent
                                entity.scale = SIMD3<Float>(repeating: scale)
                                logger.info("Scaled entity by \(scale)")
                            } else {
                                // If bounds are zero, use a default scale
                                entity.scale = SIMD3<Float>(repeating: 0.01)
                                logger.warning("Entity has zero bounds, using default scale")
                            }

                            // Center the model
                            entity.position = .zero

                            content.add(entity)
                            logger.info("Entity added to RealityView content")

                        } catch {
                            logger.error("Failed to load entity: \(error.localizedDescription)")
                            logger.error("Error details: \(String(describing: error))")

                            // Store error for display - this will trigger a view update
                            await MainActor.run {
                                modelLoadError = error.localizedDescription
                            }
                        }
                    }
                    .frame(height: 300)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Show file info
                Text("Format: \(modelURL.pathExtension.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            // Fallback if no model URL
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 300)
                .overlay {
                    VStack {
                        Image(systemName: "cube.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        Text("No model available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    // MARK: - Preview Error View

    @ViewBuilder
    private var previewErrorView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.1))
            .frame(height: 300)
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Preview Unavailable")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let error = modelLoadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Text("The model was generated successfully but cannot be previewed in this format. You can still export it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Generation Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                appModel.generationPhase = .idle
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    GenerationView()
        .environment(AppModel())
}
