//
//  ReplicateModels.swift
//  GenModel
//
//  Created by Claude Code on 24/12/25.
//

import Foundation

// MARK: - Replicate API Models

struct ReplicatePredictionRequest: Codable {
    let version: String
    let input: [String: AnyCodable]
}

struct ReplicatePredictionResponse: Codable {
    let id: String
    let status: ReplicateStatus
    let output: AnyCodable?
    let error: String?
    let urls: ReplicateURLs?
}

struct ReplicateURLs: Codable {
    let get: String
    let cancel: String
}

enum ReplicateStatus: String, Codable {
    case starting
    case processing
    case succeeded
    case failed
    case canceled
}

// MARK: - AnyCodable for dynamic JSON

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode value"))
        }
    }

    var stringValue: String? {
        value as? String
    }

    var arrayValue: [Any]? {
        value as? [Any]
    }
}

// MARK: - Replicate API Errors

enum ReplicateAPIError: LocalizedError {
    case invalidAPIToken
    case predictionFailed(message: String)
    case invalidResponse
    case networkError(underlying: Error)
    case modelDownloadFailed
    case invalidURL
    case noOutputURL
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidAPIToken:
            return "Invalid API token. Please check your Replicate API token."
        case .predictionFailed(let message):
            return "Generation failed: \(message)"
        case .invalidResponse:
            return "Invalid response from server."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .modelDownloadFailed:
            return "Failed to download the generated model."
        case .invalidURL:
            return "Invalid URL provided."
        case .noOutputURL:
            return "No output URL returned from generation."
        case .timeout:
            return "Generation timed out. Please try again."
        }
    }
}
