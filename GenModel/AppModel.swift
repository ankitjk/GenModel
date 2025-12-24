//
//  AppModel.swift
//  GenModel
//
//  Created by Ankit Kulshrestha on 22/12/25.
//

import SwiftUI

// MARK: - API Configuration
// Get your Replicate API token from https://replicate.com/account/api-tokens
enum ReplicateConfig {
    static let apiToken = "YOUR_REPLICATE_API_TOKEN_HERE"
}

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    // MARK: - Immersive Space State
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    // MARK: - Generation State
    enum GenerationPhase: Equatable {
        case idle
        case generatingPreview
        case previewReady(taskId: String)
        case generatingFinal
        case complete
        case failed(String)

        static func == (lhs: GenerationPhase, rhs: GenerationPhase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.generatingPreview, .generatingPreview): return true
            case (.previewReady(let l), .previewReady(let r)): return l == r
            case (.generatingFinal, .generatingFinal): return true
            case (.complete, .complete): return true
            case (.failed(let l), .failed(let r)): return l == r
            default: return false
            }
        }
    }

    enum InputMode {
        case text
        case image
    }

    var generationPhase: GenerationPhase = .idle
    var currentProgress: Int = 0
    var inputMode: InputMode = .text

    // Text input
    var textPrompt: String = ""
    var selectedArtStyle: ArtStyle = .realistic

    // Image input
    var selectedImageData: Data?

    // Generated model
    var generatedModelURL: URL?
    var generatedModelData: Data?
    var modelURLs: ModelURLs?

    // Active generation task (for cancellation)
    var activeGenerationTask: Task<Void, Never>?

    // API Client - Using Replicate
    let apiClient = ReplicateAPIClient(apiToken: ReplicateConfig.apiToken)

    // MARK: - Methods

    func resetGeneration() {
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        generationPhase = .idle
        currentProgress = 0
        textPrompt = ""
        selectedImageData = nil
        generatedModelURL = nil
        generatedModelData = nil
        modelURLs = nil
    }

    func startTextToGeneration() {
        guard !textPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        activeGenerationTask?.cancel()
        generationPhase = .generatingFinal
        currentProgress = 0

        activeGenerationTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Create text-to-3D prediction
                let predictionId = try await apiClient.createTextTo3D(prompt: textPrompt)

                // Step 2: Poll for completion
                let response = try await apiClient.pollUntilComplete(
                    predictionId: predictionId
                ) { progress in
                    await MainActor.run {
                        self.currentProgress = progress
                    }
                }

                // Step 3: Get output URL (GLB format from Shap-E)
                guard let output = response.output,
                      let outputUrl = output.stringValue ?? (output.arrayValue?.first as? String) else {
                    throw ReplicateAPIError.noOutputURL
                }

                let modelData = try await apiClient.downloadModel(from: outputUrl)

                // Step 4: Save to temporary file (GLB format)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("glb")
                try modelData.write(to: tempURL)

                await MainActor.run {
                    self.generatedModelData = modelData
                    self.generatedModelURL = tempURL
                    // Create ModelURLs with GLB
                    self.modelURLs = ModelURLs(
                        glb: outputUrl,
                        fbx: nil,
                        obj: nil,
                        mtl: nil,
                        usdz: nil
                    )
                    self.generationPhase = .complete
                }

            } catch is CancellationError {
                await MainActor.run {
                    self.generationPhase = .idle
                }
            } catch {
                await MainActor.run {
                    self.generationPhase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func startImageToGeneration(imageUrl: String) {
        activeGenerationTask?.cancel()
        generationPhase = .generatingFinal
        currentProgress = 0

        activeGenerationTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Create image-to-3D prediction (TripoSR)
                let predictionId = try await apiClient.createImageTo3D(imageUrl: imageUrl)

                // Step 2: Poll for completion
                let response = try await apiClient.pollUntilComplete(
                    predictionId: predictionId
                ) { progress in
                    await MainActor.run {
                        self.currentProgress = progress
                    }
                }

                // Step 3: Get output URL (GLB format from TripoSR)
                guard let output = response.output,
                      let outputUrl = output.stringValue ?? (output.arrayValue?.first as? String) else {
                    throw ReplicateAPIError.noOutputURL
                }

                let modelData = try await apiClient.downloadModel(from: outputUrl)

                // Step 4: Save to temporary file (GLB format)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("glb")
                try modelData.write(to: tempURL)

                await MainActor.run {
                    self.generatedModelData = modelData
                    self.generatedModelURL = tempURL
                    // Create ModelURLs with GLB
                    self.modelURLs = ModelURLs(
                        glb: outputUrl,
                        fbx: nil,
                        obj: nil,
                        mtl: nil,
                        usdz: nil
                    )
                    self.generationPhase = .complete
                }

            } catch is CancellationError {
                await MainActor.run {
                    self.generationPhase = .idle
                }
            } catch {
                await MainActor.run {
                    self.generationPhase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelGeneration() {
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        generationPhase = .idle
        currentProgress = 0
    }
}
