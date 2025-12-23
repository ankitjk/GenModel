//
//  MeshyModels.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import Foundation

// MARK: - Art Styles

enum ArtStyle: String, CaseIterable, Identifiable {
    case realistic = "realistic"
    case cartoon = "cartoon"
    case lowPoly = "low-poly"
    case sculpture = "sculpture"
    case pbr = "pbr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realistic: return "Realistic"
        case .cartoon: return "Cartoon"
        case .lowPoly: return "Low Poly"
        case .sculpture: return "Sculpture"
        case .pbr: return "PBR"
        }
    }
}

// MARK: - Task Status

enum MeshyTaskStatus: String, Codable {
    case pending = "PENDING"
    case inProgress = "IN_PROGRESS"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case expired = "EXPIRED"
}

// MARK: - Request Models

struct TextTo3DRequest: Codable {
    let mode: String
    let prompt: String
    let artStyle: String
    let negativePrompt: String?

    enum CodingKeys: String, CodingKey {
        case mode, prompt
        case artStyle = "art_style"
        case negativePrompt = "negative_prompt"
    }

    init(prompt: String, artStyle: ArtStyle, negativePrompt: String? = nil) {
        self.mode = "preview"
        self.prompt = prompt
        self.artStyle = artStyle.rawValue
        self.negativePrompt = negativePrompt
    }
}

struct TextTo3DRefineRequest: Codable {
    let mode: String
    let previewTaskId: String

    enum CodingKeys: String, CodingKey {
        case mode
        case previewTaskId = "preview_task_id"
    }

    init(previewTaskId: String) {
        self.mode = "refine"
        self.previewTaskId = previewTaskId
    }
}

struct ImageTo3DRequest: Codable {
    let imageUrl: String
    let enablePBR: Bool

    enum CodingKeys: String, CodingKey {
        case imageUrl = "image_url"
        case enablePBR = "enable_pbr"
    }

    init(imageUrl: String, enablePBR: Bool = true) {
        self.imageUrl = imageUrl
        self.enablePBR = enablePBR
    }
}

// MARK: - Response Models

struct TaskCreateResponse: Codable {
    let result: String
}

struct ModelURLs: Codable {
    let glb: String?
    let fbx: String?
    let obj: String?
    let mtl: String?
    let usdz: String?
}

struct TaskError: Codable {
    let message: String?
}

struct TaskStatusResponse: Codable {
    let id: String
    let status: MeshyTaskStatus
    let progress: Int
    let modelUrls: ModelURLs?
    let thumbnailUrl: String?
    let taskError: TaskError?

    enum CodingKeys: String, CodingKey {
        case id, status, progress
        case modelUrls = "model_urls"
        case thumbnailUrl = "thumbnail_url"
        case taskError = "task_error"
    }
}

// MARK: - API Errors

enum MeshyAPIError: LocalizedError {
    case invalidAPIKey
    case rateLimited(retryAfter: Int)
    case insufficientCredits
    case taskFailed(message: String)
    case invalidResponse
    case networkError(underlying: Error)
    case modelDownloadFailed
    case invalidURL
    case noModelURLs

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your Meshy API key."
        case .rateLimited(let seconds):
            return "Rate limited. Please try again in \(seconds) seconds."
        case .insufficientCredits:
            return "Insufficient credits. Please add more credits to your Meshy account."
        case .taskFailed(let message):
            return "Generation failed: \(message)"
        case .invalidResponse:
            return "Invalid response from server."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .modelDownloadFailed:
            return "Failed to download the generated model."
        case .invalidURL:
            return "Invalid URL provided."
        case .noModelURLs:
            return "No model URLs returned from generation."
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case usdz
    case glb
    case obj

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usdz: return "USDZ (Apple)"
        case .glb: return "GLB (Universal)"
        case .obj: return "OBJ (3D Software)"
        }
    }

    var fileExtension: String { rawValue }

    var mimeType: String {
        switch self {
        case .usdz: return "model/vnd.usdz+zip"
        case .glb: return "model/gltf-binary"
        case .obj: return "text/plain"
        }
    }
}
