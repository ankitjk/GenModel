//
//  MeshyAPIClient.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import Foundation

actor MeshyAPIClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.meshy.ai")!
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Text-to-3D

    func createTextTo3DPreview(prompt: String, artStyle: ArtStyle) async throws -> String {
        let url = baseURL.appendingPathComponent("/openapi/v2/text-to-3d")
        let request = TextTo3DRequest(prompt: prompt, artStyle: artStyle)
        let response: TaskCreateResponse = try await performRequest(url: url, method: "POST", body: request)
        return response.result
    }

    func createTextTo3DRefine(previewTaskId: String) async throws -> String {
        let url = baseURL.appendingPathComponent("/openapi/v2/text-to-3d")
        let request = TextTo3DRefineRequest(previewTaskId: previewTaskId)
        let response: TaskCreateResponse = try await performRequest(url: url, method: "POST", body: request)
        return response.result
    }

    // MARK: - Image-to-3D

    func createImageTo3D(imageUrl: String) async throws -> String {
        let url = baseURL.appendingPathComponent("/openapi/v2/image-to-3d")
        let request = ImageTo3DRequest(imageUrl: imageUrl)
        let response: TaskCreateResponse = try await performRequest(url: url, method: "POST", body: request)
        return response.result
    }

    // MARK: - Task Status

    func getTextTo3DTaskStatus(taskId: String) async throws -> TaskStatusResponse {
        let url = baseURL.appendingPathComponent("/openapi/v2/text-to-3d/\(taskId)")
        return try await performRequest(url: url, method: "GET")
    }

    func getImageTo3DTaskStatus(taskId: String) async throws -> TaskStatusResponse {
        let url = baseURL.appendingPathComponent("/openapi/v2/image-to-3d/\(taskId)")
        return try await performRequest(url: url, method: "GET")
    }

    // MARK: - Model Download

    func downloadModel(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw MeshyAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeshyAPIError.modelDownloadFailed
        }

        return data
    }

    // MARK: - Private Helpers

    private func performRequest<T: Decodable>(url: URL, method: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await executeRequest(request)
    }

    private func performRequest<T: Decodable, B: Encodable>(url: URL, method: String, body: B) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        return try await executeRequest(request)
    }

    private func executeRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeshyAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)

        case 401:
            throw MeshyAPIError.invalidAPIKey

        case 402:
            throw MeshyAPIError.insufficientCredits

        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0) } ?? 60
            throw MeshyAPIError.rateLimited(retryAfter: retryAfter)

        default:
            if let errorResponse = try? JSONDecoder().decode(TaskError.self, from: data),
               let message = errorResponse.message {
                throw MeshyAPIError.taskFailed(message: message)
            }
            throw MeshyAPIError.invalidResponse
        }
    }
}

// MARK: - Polling Extension

extension MeshyAPIClient {
    enum TaskType {
        case textTo3D
        case imageTo3D
    }

    func pollUntilComplete(
        taskId: String,
        taskType: TaskType,
        onProgress: @escaping (Int) async -> Void
    ) async throws -> TaskStatusResponse {
        var pollInterval: TimeInterval = 2.0
        let maxPollInterval: TimeInterval = 10.0
        let maxAttempts = 180 // ~30 minutes max

        for _ in 0..<maxAttempts {
            let response: TaskStatusResponse
            switch taskType {
            case .textTo3D:
                response = try await getTextTo3DTaskStatus(taskId: taskId)
            case .imageTo3D:
                response = try await getImageTo3DTaskStatus(taskId: taskId)
            }

            await onProgress(response.progress)

            switch response.status {
            case .succeeded:
                return response

            case .failed:
                let message = response.taskError?.message ?? "Unknown error"
                throw MeshyAPIError.taskFailed(message: message)

            case .expired:
                throw MeshyAPIError.taskFailed(message: "Task expired")

            case .pending, .inProgress:
                try await Task.sleep(for: .seconds(pollInterval))
                pollInterval = min(pollInterval * 1.5, maxPollInterval)
            }

            try Task.checkCancellation()
        }

        throw MeshyAPIError.taskFailed(message: "Generation timed out")
    }
}
