//
//  ImmersiveView.swift
//  GenModel
//
//  Created by Ankit Kulshrestha on 22/12/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            // Load the generated model if available, otherwise load default
            if let modelURL = appModel.generatedModelURL {
                do {
                    let entity = try await Entity(contentsOf: modelURL)
                    // Position the model in front of the user
                    entity.position = SIMD3<Float>(0, 1.5, -1.5)
                    // Scale appropriately for viewing
                    entity.scale = SIMD3<Float>(repeating: 1.0)
                    content.add(entity)
                } catch {
                    print("Failed to load generated model: \(error)")
                    // Fall back to default immersive content
                    await loadDefaultContent(content: content)
                }
            } else {
                // Load default immersive content when no generated model
                await loadDefaultContent(content: content)
            }
        } update: { content in
            // Handle updates when the model changes
            // For PoC, we don't dynamically update - user reopens immersive space
        }
    }

    private func loadDefaultContent(content: RealityViewContent) async {
        if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
            content.add(immersiveContentEntity)
        }
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
