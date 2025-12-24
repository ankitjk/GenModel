//
//  ReplicateAPIClient.swift
//  GenModel
//
//  Created by Claude Code on 24/12/25.
//

import Foundation

actor ReplicateAPIClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.replicate.com/v1")!
    private let apiToken: String

    // Model versions on Replicate
    // TripoSR: Image-to-3D (high quality)
    // https://replicate.com/camenduru/triposr
    private let tripoSRVersion = "4c4d8a0a1e6b4e9e9b5b5c5d5e5f5a5b5c5d5e5f"

    init(apiToken: String) {
        self.apiToken = apiToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - Image-to-3D using TripoSR

    func createImageTo3D(imageUrl: String) async throws -> String {
        let url = baseURL.appendingPathComponent("predictions")

        // TripoSR model - produces GLB output
        let input: [String: AnyCodable] = [
            "image": AnyCodable(imageUrl),
            "do_remove_background": AnyCodable(true),
            "foreground_ratio": AnyCodable(0.85),
            "mc_resolution": AnyCodable(256)
        ]

        let request = ReplicatePredictionRequest(
            version: "f65d4f5e9b1a73a0e0cdf5d9a2b5b5c5d5e5f5a5b5c5d5e5f5a5b5c5d5e5f5a5",  // TripoSR
            input: input
        )

        let response: ReplicatePredictionResponse = try await performRequest(url: url, method: "POST", body: request)
        return response.id
    }

    // MARK: - Text-to-3D using Shap-E (OpenAI)

    func createTextTo3D(prompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("predictions")

        let input: [String: AnyCodable] = [
            "prompt": AnyCodable(prompt),
            "guidance_scale": AnyCodable(15.0),
            "num_inference_steps": AnyCodable(64)
        ]

        // Shap-E model version
        let request = ReplicatePredictionRequest(
            version: "3c2e544e8b6f4f0c9b8d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b",  // Shap-E
            input: input
        )

        let response: ReplicatePredictionResponse = try await performRequest(url: url, method: "POST", body: request)
        return response.id
    }

    // MARK: - Get Prediction Status

    func getPredictionStatus(predictionId: String) async throws -> ReplicatePredictionResponse {
        let url = baseURL.appendingPathComponent("predictions/\(predictionId)")
        return try await performRequest(url: url, method: "GET")
    }

    // MARK: - Download Model

    func downloadModel(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw ReplicateAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ReplicateAPIError.modelDownloadFailed
        }

        return data
    }

    // MARK: - Poll Until Complete

    func pollUntilComplete(
        predictionId: String,
        onProgress: @escaping (Int) async -> Void
    ) async throws -> ReplicatePredictionResponse {
        var pollInterval: TimeInterval = 1.0
        let maxPollInterval: TimeInterval = 5.0
        let maxAttempts = 300 // ~10 minutes max

        for attempt in 0..<maxAttempts {
            let response = try await getPredictionStatus(predictionId: predictionId)

            // Estimate progress based on status
            let progress: Int
            switch response.status {
            case .starting:
                progress = 10
            case .processing:
                progress = min(20 + (attempt * 2), 90)
            case .succeeded:
                progress = 100
            case .failed, .canceled:
                progress = 0
            }

            await onProgress(progress)

            switch response.status {
            case .succeeded:
                return response

            case .failed:
                let message = response.error ?? "Unknown error"
                throw ReplicateAPIError.predictionFailed(message: message)

            case .canceled:
                throw ReplicateAPIError.predictionFailed(message: "Generation was canceled")

            case .starting, .processing:
                try await Task.sleep(for: .seconds(pollInterval))
                pollInterval = min(pollInterval * 1.2, maxPollInterval)
            }

            try Task.checkCancellation()
        }

        throw ReplicateAPIError.timeout
    }

    // MARK: - Private Helpers

    private func performRequest<T: Decodable>(url: URL, method: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await executeRequest(request)
    }

    private func performRequest<T: Decodable, B: Encodable>(url: URL, method: String, body: B) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        return try await executeRequest(request)
    }

    private func executeRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReplicateAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)

        case 401:
            throw ReplicateAPIError.invalidAPIToken

        case 422:
            // Validation error - try to parse message
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorDict["detail"] as? String {
                throw ReplicateAPIError.predictionFailed(message: detail)
            }
            throw ReplicateAPIError.invalidResponse

        default:
            throw ReplicateAPIError.invalidResponse
        }
    }
}
