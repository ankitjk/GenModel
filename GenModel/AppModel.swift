//
//  AppModel.swift
//  GenModel
//
//  Created by Ankit Kulshrestha on 22/12/25.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.genmodel", category: "AppModel")

// MARK: - API Configuration
// The token is read from GenModel/Secrets.plist, which is git-ignored.
// Copy Secrets.example.plist there and paste your token from
// https://replicate.com/account/api-tokens
enum ReplicateConfig {
    static let apiToken: String = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let token = plist["REPLICATE_API_TOKEN"] as? String,
              !token.isEmpty, !token.hasSuffix("your_token_here") else {
            logger.error("No Replicate API token found. Add GenModel/Secrets.plist (see Secrets.example.plist).")
            return ""
        }
        return token
    }()
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
        guard !textPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("Text prompt is empty, not starting generation")
            return
        }

        logger.info("Starting text-to-3D generation with prompt: \(self.textPrompt)")
        activeGenerationTask?.cancel()
        generationPhase = .generatingFinal
        currentProgress = 0

        activeGenerationTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Create text-to-3D prediction
                logger.info("Step 1: Creating prediction...")
                let predictionId = try await apiClient.createTextTo3D(prompt: textPrompt)
                logger.info("Prediction created: \(predictionId)")

                // Step 2: Poll for completion
                logger.info("Step 2: Polling for completion...")
                let response = try await apiClient.pollUntilComplete(
                    predictionId: predictionId
                ) { progress in
                    await MainActor.run {
                        self.currentProgress = progress
                    }
                }
                logger.info("Polling complete, status: \(response.status.rawValue)")

                // Step 3: Get output URL
                logger.info("Step 3: Extracting output URL...")
                guard let output = response.output else {
                    logger.error("No output in response")
                    throw ReplicateAPIError.noOutputURL
                }

                // Log the full output for debugging
                if let array = output.arrayValue {
                    logger.info("Output is an array with \(array.count) items")
                    for (i, item) in array.enumerated() {
                        logger.info("Output[\(i)]: \(String(describing: item))")
                    }
                } else if let str = output.stringValue {
                    logger.info("Output is a string: \(str)")
                }

                // Find the mesh URL (look for .ply, .glb, or .obj files)
                var meshUrl: String?
                if let array = output.arrayValue {
                    // Look through array for mesh file URLs
                    for item in array {
                        if let urlStr = item as? String {
                            let lowered = urlStr.lowercased()
                            if lowered.contains(".glb") || lowered.contains(".ply") ||
                               lowered.contains(".obj") || lowered.contains(".gltf") {
                                meshUrl = urlStr
                                break
                            }
                        }
                    }
                    // If no mesh found, take the first URL
                    if meshUrl == nil {
                        meshUrl = array.first as? String
                    }
                } else {
                    meshUrl = output.stringValue
                }

                guard let outputUrl = meshUrl else {
                    logger.error("No mesh URL found in output")
                    throw ReplicateAPIError.noOutputURL
                }
                logger.info("Selected mesh URL: \(outputUrl)")

                // Detect file extension from URL
                let urlComponents = outputUrl.components(separatedBy: ".")
                let detectedExtension = urlComponents.last?.lowercased() ?? "glb"
                logger.info("Detected file extension: \(detectedExtension)")

                logger.info("Step 4: Downloading model...")
                let modelData = try await apiClient.downloadModel(from: outputUrl)
                logger.info("Model downloaded: \(modelData.count) bytes")

                // Detect actual file format from content (more reliable than URL extension)
                var actualExtension = "glb" // default
                if modelData.count >= 4 {
                    let header = modelData.prefix(4)
                    let headerHex = header.map { String(format: "%02X", $0) }.joined(separator: " ")
                    logger.info("File header (first 4 bytes): \(headerHex)")

                    // GLB files start with "glTF" magic bytes: 0x67 0x6C 0x54 0x46
                    if header[0] == 0x67 && header[1] == 0x6C && header[2] == 0x54 && header[3] == 0x46 {
                        logger.info("File format confirmed: GLB (glTF binary)")
                        actualExtension = "glb"
                    } else if header[0] == 0x70 && header[1] == 0x6C && header[2] == 0x79 {
                        // PLY files start with "ply"
                        logger.info("File format detected: PLY")
                        actualExtension = "ply"
                    } else if let firstChar = String(data: modelData.prefix(1), encoding: .ascii),
                              firstChar == "v" || firstChar == "#" || firstChar == "o" || firstChar == "m" {
                        // OBJ files typically start with v (vertex), # (comment), o (object), or mtllib
                        logger.info("File format detected: OBJ (ASCII text)")
                        actualExtension = "obj"
                    }
                }
                logger.info("Using file extension: \(actualExtension)")

                // Step 5: Save to temporary file with detected extension
                let fileExtension = actualExtension
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension)
                try modelData.write(to: tempURL)
                logger.info("Model saved to: \(tempURL.path)")

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
                    logger.info("Generation complete!")
                }

            } catch is CancellationError {
                logger.info("Generation was canceled by user")
                await MainActor.run {
                    self.generationPhase = .idle
                }
            } catch {
                logger.error("Generation failed: \(error.localizedDescription)")
                logger.error("Error details: \(String(describing: error))")
                await MainActor.run {
                    self.generationPhase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func startImageToGeneration(imageUrl: String) {
        logger.info("Starting image-to-3D generation with URL: \(imageUrl)")
        startImageGeneration { apiClient in
            try await apiClient.createImageTo3D(imageUrl: imageUrl)
        }
    }

    func startImageToGeneration(imageData: Data) {
        logger.info("Starting image-to-3D generation with local image data (\(imageData.count) bytes)")
        startImageGeneration { apiClient in
            try await apiClient.createImageTo3D(imageData: imageData)
        }
    }

    private func startImageGeneration(createPrediction: @escaping (ReplicateAPIClient) async throws -> String) {
        activeGenerationTask?.cancel()
        generationPhase = .generatingFinal
        currentProgress = 0

        activeGenerationTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Create image-to-3D prediction
                logger.info("Step 1: Creating prediction...")
                let predictionId = try await createPrediction(apiClient)
                logger.info("Prediction created: \(predictionId)")

                // Step 2: Poll for completion
                logger.info("Step 2: Polling for completion...")
                let response = try await apiClient.pollUntilComplete(
                    predictionId: predictionId
                ) { progress in
                    await MainActor.run {
                        self.currentProgress = progress
                    }
                }
                logger.info("Polling complete, status: \(response.status.rawValue)")

                // Step 3: Get output URL (TRELLIS outputs GLB)
                logger.info("Step 3: Extracting output URL...")
                guard let output = response.output else {
                    logger.error("No output in response")
                    throw ReplicateAPIError.noOutputURL
                }

                // Log the full output for debugging
                if let array = output.arrayValue {
                    logger.info("Output is an array with \(array.count) items")
                    for (i, item) in array.enumerated() {
                        logger.info("Output[\(i)]: \(String(describing: item))")
                    }
                } else if let str = output.stringValue {
                    logger.info("Output is a string: \(str)")
                }

                // TRELLIS outputs model_file as the GLB URL
                var meshUrl: String?
                if let dict = output.value as? [String: Any] {
                    // TRELLIS returns a dict with model_file key
                    if let modelFile = dict["model_file"] as? String {
                        meshUrl = modelFile
                        logger.info("Found model_file: \(modelFile)")
                    }
                } else if let array = output.arrayValue {
                    // Look for GLB URL in array
                    for item in array {
                        if let urlStr = item as? String, urlStr.lowercased().contains(".glb") {
                            meshUrl = urlStr
                            break
                        }
                    }
                    if meshUrl == nil {
                        meshUrl = array.first as? String
                    }
                } else {
                    meshUrl = output.stringValue
                }

                guard let outputUrl = meshUrl else {
                    logger.error("No mesh URL found in output")
                    throw ReplicateAPIError.noOutputURL
                }
                logger.info("Selected mesh URL: \(outputUrl)")

                logger.info("Step 4: Downloading model...")
                let modelData = try await apiClient.downloadModel(from: outputUrl)
                logger.info("Model downloaded: \(modelData.count) bytes")

                // Detect actual file format from content (more reliable than URL extension)
                var actualExtension = "glb" // default
                if modelData.count >= 4 {
                    let header = modelData.prefix(4)
                    let headerHex = header.map { String(format: "%02X", $0) }.joined(separator: " ")
                    logger.info("File header (first 4 bytes): \(headerHex)")

                    // GLB files start with "glTF" magic bytes: 0x67 0x6C 0x54 0x46
                    if header[0] == 0x67 && header[1] == 0x6C && header[2] == 0x54 && header[3] == 0x46 {
                        logger.info("File format confirmed: GLB (glTF binary)")
                        actualExtension = "glb"
                    } else if header[0] == 0x70 && header[1] == 0x6C && header[2] == 0x79 {
                        // PLY files start with "ply"
                        logger.info("File format detected: PLY")
                        actualExtension = "ply"
                    } else if let firstChar = String(data: modelData.prefix(1), encoding: .ascii),
                              firstChar == "v" || firstChar == "#" || firstChar == "o" || firstChar == "m" {
                        // OBJ files typically start with v (vertex), # (comment), o (object), or mtllib
                        logger.info("File format detected: OBJ (ASCII text)")
                        actualExtension = "obj"
                    }
                }
                logger.info("Using file extension: \(actualExtension)")

                // Step 5: Save to temporary file with detected extension
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(actualExtension)
                try modelData.write(to: tempURL)
                logger.info("Model saved to: \(tempURL.path)")

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
                    logger.info("Generation complete!")
                }

            } catch is CancellationError {
                logger.info("Generation was canceled by user")
                await MainActor.run {
                    self.generationPhase = .idle
                }
            } catch {
                logger.error("Generation failed: \(error.localizedDescription)")
                logger.error("Error details: \(String(describing: error))")
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
