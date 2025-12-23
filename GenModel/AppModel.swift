//
//  AppModel.swift
//  GenModel
//
//  Created by Ankit Kulshrestha on 22/12/25.
//

import SwiftUI

// MARK: - API Configuration
// TODO: Replace with your Meshy API key from https://www.meshy.ai/
enum MeshyConfig {
    static let apiKey = "YOUR_MESHY_API_KEY_HERE"
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

    // API Client
    lazy var apiClient: MeshyAPIClient = {
        MeshyAPIClient(apiKey: MeshyConfig.apiKey)
    }()

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
        generationPhase = .generatingPreview
        currentProgress = 0

        activeGenerationTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Create preview task
                let taskId = try await apiClient.createTextTo3DPreview(
                    prompt: textPrompt,
                    artStyle: selectedArtStyle
                )

                // Step 2: Poll for preview completion
                let previewResponse = try await apiClient.pollUntilComplete(
                    taskId: taskId,
                    taskType: .textTo3D
                ) { progress in
                    await MainActor.run {
                        self.currentProgress = progress
                    }
                }

                await MainActor.run {
                    self.generationPhase = .previewReady(taskId: taskId)
                }

                // Step 3: Automatically refine (for PoC, skip manual approval)
                await MainActor.run {
                    self.generationPhase = .generatingFinal
                    self.currentProgress = 0
                }

                let refineTaskId = try await apiClient.createTextTo3DRefine(previewTaskId: taskId)

                // Step 4: Poll for refine completion
                let finalResponse = try await apiClient.pollUntilComplete(
                    taskId: refineTaskId,
                    taskType: .textTo3D
                ) { progress in
                    await MainActor.run {
                        self.currentProgress = progress
                    }
                }

                // Step 5: Download USDZ model
                guard let modelUrls = finalResponse.modelUrls,
                      let usdzUrl = modelUrls.usdz else {
                    throw MeshyAPIError.noModelURLs
                }

                let modelData = try await apiClient.downloadModel(from: usdzUrl)

                // Step 6: Save to temporary file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("usdz")
                try modelData.write(to: tempURL)

                await MainActor.run {
                    self.generatedModelData = modelData
                    self.generatedModelURL = tempURL
                    self.modelURLs = modelUrls
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
                // Step 1: Create image-to-3D task
                let taskId = try await apiClient.createImageTo3D(imageUrl: imageUrl)

                // Step 2: Poll for completion
                let response = try await apiClient.pollUntilComplete(
                    taskId: taskId,
                    taskType: .imageTo3D
                ) { progress in
                    await MainActor.run {
                        self.currentProgress = progress
                    }
                }

                // Step 3: Download USDZ model
                guard let modelUrls = response.modelUrls,
                      let usdzUrl = modelUrls.usdz else {
                    throw MeshyAPIError.noModelURLs
                }

                let modelData = try await apiClient.downloadModel(from: usdzUrl)

                // Step 4: Save to temporary file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("usdz")
                try modelData.write(to: tempURL)

                await MainActor.run {
                    self.generatedModelData = modelData
                    self.generatedModelURL = tempURL
                    self.modelURLs = modelUrls
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
