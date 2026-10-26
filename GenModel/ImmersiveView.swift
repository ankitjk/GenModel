//
//  ImmersiveView.swift
//  GenModel
//
//  Created by Ankit Kulshrestha on 22/12/25.
//

import SwiftUI
import RealityKit
import RealityKitContent
import os.log

private let logger = Logger(subsystem: "com.genmodel", category: "ImmersiveView")

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var loadError: String?

    var body: some View {
        ZStack {
            RealityView { content in
                // Load the generated model if available, otherwise load default
                if let modelURL = appModel.generatedModelURL {
                    logger.info("Attempting to load model from: \(modelURL.path)")
                    logger.info("File exists: \(FileManager.default.fileExists(atPath: modelURL.path))")

                    do {
                        // Use ModelLoader for multi-format support (USDZ, GLB, OBJ, PLY, etc.)
                        let entity = try await ModelLoader.loadEntity(from: modelURL)
                        logger.info("Successfully loaded entity via ModelLoader")

                        // Position the model in front of the user
                        entity.position = SIMD3<Float>(0, 1.5, -1.5)

                        // Auto-scale based on model bounds
                        let bounds = entity.visualBounds(relativeTo: nil)
                        let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                        if maxExtent > 0 {
                            let targetSize: Float = 0.5 // 0.5 meters
                            let scale = targetSize / maxExtent
                            entity.scale = SIMD3<Float>(repeating: scale)
                            logger.info("Scaled model by \(scale) (original extent: \(maxExtent))")
                        }

                        // Add ground shadow for depth perception
                        entity.components.set(GroundingShadowComponent(castsShadow: true))

                        content.add(entity)
                        logger.info("Entity added to scene successfully")

                    } catch {
                        logger.error("Failed to load model: \(error.localizedDescription)")
                        logger.error("Error details: \(String(describing: error))")

                        // Store error for display
                        await MainActor.run {
                            loadError = error.localizedDescription
                        }

                        // Load default content as fallback (without placeholder cube)
                        await loadDefaultContent(content: content)
                    }
                } else {
                    logger.info("No generated model URL, loading default content")
                    // Load default immersive content when no generated model
                    await loadDefaultContent(content: content)
                }
            } update: { _ in
                // Handle updates when the model changes
                // For PoC, we don't dynamically update - user reopens immersive space
            }

            // Show error overlay if model failed to load
            if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)

                    Text("Unable to Display Model")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Text("This format cannot be viewed in immersive space. Try exporting to a different format.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private func loadDefaultContent(content: RealityViewContent) async {
        logger.info("Loading default immersive content")
        if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
            content.add(immersiveContentEntity)
            logger.info("Default content loaded successfully")
        } else {
            logger.warning("Failed to load default immersive content")
        }
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
