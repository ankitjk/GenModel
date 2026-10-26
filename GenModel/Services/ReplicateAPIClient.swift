//
//  ReplicateAPIClient.swift
//  GenModel
//
//  Created by Claude Code on 24/12/25.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.genmodel", category: "ReplicateAPI")

actor ReplicateAPIClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.replicate.com/v1")!
    private let apiToken: String

    // Model versions on Replicate (verified working versions)
    // Shap-E: Text-to-3D by cjwbw
    // https://replicate.com/cjwbw/shap-e
    private let shapEVersion = "5957069d5c509126a73c7cb68abcddbb985aeefa4d318e7c63ec1352ce6da68c"

    // TRELLIS: Image-to-3D by firtoz (high quality, outputs GLB)
    // https://replicate.com/firtoz/trellis
    private let trellisVersion = "e8f6c45206993f297372f5436b90350817bd9b4a0d52d2a76df50c1c8afa2b3c"

    init(apiToken: String) {
        self.apiToken = apiToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - Image-to-3D using TRELLIS

    /// Create image-to-3D prediction from a URL
    func createImageTo3D(imageUrl: String) async throws -> String {
        logger.info("Creating image-to-3D prediction for URL: \(imageUrl)")
        return try await createImageTo3DPrediction(imageInput: imageUrl)
    }

    /// Create image-to-3D prediction from local image data (uses data URI)
    func createImageTo3D(imageData: Data) async throws -> String {
        logger.info("Creating image-to-3D prediction from image data (\(imageData.count) bytes)")

        // Detect image type and create data URI
        let mimeType = detectImageMimeType(data: imageData)
        let base64String = imageData.base64EncodedString()
        let dataUri = "data:\(mimeType);base64,\(base64String)"

        logger.info("Created data URI with mime type: \(mimeType)")
        return try await createImageTo3DPrediction(imageInput: dataUri)
    }

    private func createImageTo3DPrediction(imageInput: String) async throws -> String {
        let url = baseURL.appendingPathComponent("predictions")

        // TRELLIS model - produces GLB output
        let input: [String: AnyCodable] = [
            "images": AnyCodable([imageInput]),
            "generate_model": AnyCodable(true),
            "generate_color": AnyCodable(true),
            "texture_size": AnyCodable(1024)
        ]

        let request = ReplicatePredictionRequest(
            version: trellisVersion,
            input: input
        )

        let response: ReplicatePredictionResponse = try await performRequest(url: url, method: "POST", body: request)
        logger.info("Image-to-3D prediction created with ID: \(response.id)")
        return response.id
    }

    /// Detect MIME type from image data header bytes
    private func detectImageMimeType(data: Data) -> String {
        guard data.count >= 4 else { return "image/jpeg" }

        let header = [UInt8](data.prefix(4))

        // PNG: 89 50 4E 47
        if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 {
            return "image/png"
        }
        // JPEG: FF D8 FF
        if header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF {
            return "image/jpeg"
        }
        // GIF: 47 49 46 38
        if header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x38 {
            return "image/gif"
        }
        // WebP: 52 49 46 46 ... 57 45 42 50
        if header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 {
            return "image/webp"
        }

        return "image/jpeg" // default
    }

    // MARK: - Text-to-3D using Shap-E (OpenAI)

    func createTextTo3D(prompt: String) async throws -> String {
        logger.info("Creating text-to-3D prediction for prompt: \(prompt)")
        let url = baseURL.appendingPathComponent("predictions")

        let input: [String: AnyCodable] = [
            "prompt": AnyCodable(prompt),
            "guidance_scale": AnyCodable(15.0),
            "save_mesh": AnyCodable(true),
            "batch_size": AnyCodable(1),
            "render_mode": AnyCodable("stf"),
            "render_size": AnyCodable(128)
        ]

        let request = ReplicatePredictionRequest(
            version: shapEVersion,
            input: input
        )

        let response: ReplicatePredictionResponse = try await performRequest(url: url, method: "POST", body: request)
        logger.info("Text-to-3D prediction created with ID: \(response.id)")
        return response.id
    }

    // MARK: - Get Prediction Status

    func getPredictionStatus(predictionId: String) async throws -> ReplicatePredictionResponse {
        let url = baseURL.appendingPathComponent("predictions/\(predictionId)")
        return try await performRequest(url: url, method: "GET")
    }

    // MARK: - Download Model

    func downloadModel(from urlString: String) async throws -> Data {
        logger.info("Downloading model from: \(urlString)")
        guard let url = URL(string: urlString) else {
            logger.error("Invalid model URL: \(urlString)")
            throw ReplicateAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Model download failed with status: \(statusCode)")
            throw ReplicateAPIError.modelDownloadFailed
        }

        logger.info("Model downloaded successfully, size: \(data.count) bytes")
        return data
    }

    // MARK: - Poll Until Complete

    func pollUntilComplete(
        predictionId: String,
        onProgress: @escaping (Int) async -> Void
    ) async throws -> ReplicatePredictionResponse {
        logger.info("Starting to poll prediction: \(predictionId)")
        var pollInterval: TimeInterval = 1.0
        let maxPollInterval: TimeInterval = 5.0
        let maxAttempts = 300 // ~10 minutes max

        for attempt in 0..<maxAttempts {
            let response = try await getPredictionStatus(predictionId: predictionId)
            logger.debug("Poll attempt \(attempt): status=\(response.status.rawValue)")

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
                logger.info("Prediction succeeded: \(predictionId)")
                if let output = response.output {
                    logger.info("Output: \(String(describing: output.stringValue ?? output.arrayValue?.description ?? "unknown"))")
                }
                return response

            case .failed:
                let message = response.error ?? "Unknown error"
                logger.error("Prediction failed: \(message)")
                throw ReplicateAPIError.predictionFailed(message: message)

            case .canceled:
                logger.warning("Prediction was canceled")
                throw ReplicateAPIError.predictionFailed(message: "Generation was canceled")

            case .starting, .processing:
                try await Task.sleep(for: .seconds(pollInterval))
                pollInterval = min(pollInterval * 1.2, maxPollInterval)
            }

            try Task.checkCancellation()
        }

        logger.error("Prediction timed out after \(maxAttempts) attempts")
        throw ReplicateAPIError.timeout
    }

    // MARK: - Private Helpers

    private func performRequest<T: Decodable>(url: URL, method: String) async throws -> T {
        guard !apiToken.isEmpty else { throw ReplicateAPIError.missingAPIToken }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await executeRequest(request)
    }

    private func performRequest<T: Decodable, B: Encodable>(url: URL, method: String, body: B) async throws -> T {
        guard !apiToken.isEmpty else { throw ReplicateAPIError.missingAPIToken }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        return try await executeRequest(request)
    }

    private func executeRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        logger.debug("Executing request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type (not HTTP)")
            throw ReplicateAPIError.invalidResponse
        }

        logger.debug("Response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                let responseString = String(data: data, encoding: .utf8) ?? "unable to decode"
                logger.error("JSON decode error: \(error.localizedDescription)")
                logger.error("Response body: \(responseString)")
                throw error
            }

        case 401:
            logger.error("Invalid API token (401)")
            throw ReplicateAPIError.invalidAPIToken

        case 402:
            let responseString = String(data: data, encoding: .utf8) ?? "unable to decode"
            logger.error("Payment required (402) - billing not set up. Response: \(responseString)")
            throw ReplicateAPIError.predictionFailed(message: "Payment required - please set up billing at replicate.com/account/billing")

        case 422:
            // Validation error - try to parse message
            let responseString = String(data: data, encoding: .utf8) ?? "unable to decode"
            logger.error("Validation error (422): \(responseString)")
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorDict["detail"] as? String {
                throw ReplicateAPIError.predictionFailed(message: detail)
            }
            throw ReplicateAPIError.invalidResponse

        default:
            let responseString = String(data: data, encoding: .utf8) ?? "unable to decode"
            logger.error("Unexpected status \(httpResponse.statusCode): \(responseString)")
            throw ReplicateAPIError.invalidResponse
        }
    }
}
