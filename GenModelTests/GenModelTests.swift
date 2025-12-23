//
//  GenModelTests.swift
//  GenModelTests
//
//  Created by Ankit Kulshrestha on 22/12/25.
//

import Testing
import Foundation
@testable import GenModel

// MARK: - MeshyModels Tests

struct MeshyModelsTests {

    // MARK: - ArtStyle Tests

    @Test func artStyleRawValues() {
        #expect(ArtStyle.realistic.rawValue == "realistic")
        #expect(ArtStyle.cartoon.rawValue == "cartoon")
        #expect(ArtStyle.lowPoly.rawValue == "low-poly")
        #expect(ArtStyle.sculpture.rawValue == "sculpture")
        #expect(ArtStyle.pbr.rawValue == "pbr")
    }

    @Test func artStyleDisplayNames() {
        #expect(ArtStyle.realistic.displayName == "Realistic")
        #expect(ArtStyle.cartoon.displayName == "Cartoon")
        #expect(ArtStyle.lowPoly.displayName == "Low Poly")
        #expect(ArtStyle.sculpture.displayName == "Sculpture")
        #expect(ArtStyle.pbr.displayName == "PBR")
    }

    @Test func artStyleAllCasesCount() {
        #expect(ArtStyle.allCases.count == 5)
    }

    // MARK: - ExportFormat Tests

    @Test func exportFormatFileExtensions() {
        #expect(ExportFormat.usdz.fileExtension == "usdz")
        #expect(ExportFormat.glb.fileExtension == "glb")
        #expect(ExportFormat.obj.fileExtension == "obj")
    }

    @Test func exportFormatDisplayNames() {
        #expect(ExportFormat.usdz.displayName == "USDZ (Apple)")
        #expect(ExportFormat.glb.displayName == "GLB (Universal)")
        #expect(ExportFormat.obj.displayName == "OBJ (3D Software)")
    }

    @Test func exportFormatMimeTypes() {
        #expect(ExportFormat.usdz.mimeType == "model/vnd.usdz+zip")
        #expect(ExportFormat.glb.mimeType == "model/gltf-binary")
        #expect(ExportFormat.obj.mimeType == "text/plain")
    }

    // MARK: - MeshyTaskStatus Tests

    @Test func taskStatusDecoding() throws {
        let json = """
        {
            "id": "task-123",
            "status": "SUCCEEDED",
            "progress": 100,
            "model_urls": {
                "usdz": "https://example.com/model.usdz",
                "glb": "https://example.com/model.glb",
                "obj": "https://example.com/model.obj"
            },
            "thumbnail_url": "https://example.com/thumb.png"
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(TaskStatusResponse.self, from: json.data(using: .utf8)!)

        #expect(response.id == "task-123")
        #expect(response.status == .succeeded)
        #expect(response.progress == 100)
        #expect(response.modelUrls?.usdz == "https://example.com/model.usdz")
        #expect(response.modelUrls?.glb == "https://example.com/model.glb")
        #expect(response.modelUrls?.obj == "https://example.com/model.obj")
        #expect(response.thumbnailUrl == "https://example.com/thumb.png")
    }

    @Test func taskStatusPendingDecoding() throws {
        let json = """
        {
            "id": "task-456",
            "status": "PENDING",
            "progress": 0
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(TaskStatusResponse.self, from: json.data(using: .utf8)!)

        #expect(response.id == "task-456")
        #expect(response.status == .pending)
        #expect(response.progress == 0)
        #expect(response.modelUrls == nil)
    }

    @Test func taskStatusInProgressDecoding() throws {
        let json = """
        {
            "id": "task-789",
            "status": "IN_PROGRESS",
            "progress": 50
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(TaskStatusResponse.self, from: json.data(using: .utf8)!)

        #expect(response.status == .inProgress)
        #expect(response.progress == 50)
    }

    @Test func taskStatusFailedDecoding() throws {
        let json = """
        {
            "id": "task-error",
            "status": "FAILED",
            "progress": 25,
            "task_error": {
                "message": "Generation failed due to invalid prompt"
            }
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(TaskStatusResponse.self, from: json.data(using: .utf8)!)

        #expect(response.status == .failed)
        #expect(response.taskError?.message == "Generation failed due to invalid prompt")
    }

    // MARK: - Request Encoding Tests

    @Test func textTo3DRequestEncoding() throws {
        let request = TextTo3DRequest(prompt: "A red sports car", artStyle: .realistic)

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["mode"] as? String == "preview")
        #expect(json["prompt"] as? String == "A red sports car")
        #expect(json["art_style"] as? String == "realistic")
    }

    @Test func textTo3DRefineRequestEncoding() throws {
        let request = TextTo3DRefineRequest(previewTaskId: "preview-123")

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["mode"] as? String == "refine")
        #expect(json["preview_task_id"] as? String == "preview-123")
    }

    @Test func imageTo3DRequestEncoding() throws {
        let request = ImageTo3DRequest(imageUrl: "https://example.com/image.jpg", enablePBR: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["image_url"] as? String == "https://example.com/image.jpg")
        #expect(json["enable_pbr"] as? Bool == true)
    }

    // MARK: - MeshyAPIError Tests

    @Test func apiErrorDescriptions() {
        #expect(MeshyAPIError.invalidAPIKey.errorDescription?.contains("Invalid API key") == true)
        #expect(MeshyAPIError.rateLimited(retryAfter: 60).errorDescription?.contains("60 seconds") == true)
        #expect(MeshyAPIError.insufficientCredits.errorDescription?.contains("Insufficient credits") == true)
        #expect(MeshyAPIError.taskFailed(message: "Test error").errorDescription?.contains("Test error") == true)
        #expect(MeshyAPIError.invalidResponse.errorDescription?.contains("Invalid response") == true)
        #expect(MeshyAPIError.modelDownloadFailed.errorDescription?.contains("Failed to download") == true)
        #expect(MeshyAPIError.invalidURL.errorDescription?.contains("Invalid URL") == true)
        #expect(MeshyAPIError.noModelURLs.errorDescription?.contains("No model URLs") == true)
    }
}

// MARK: - AppModel Tests

@MainActor
struct AppModelTests {

    @Test func initialState() {
        let appModel = AppModel()

        #expect(appModel.generationPhase == .idle)
        #expect(appModel.currentProgress == 0)
        #expect(appModel.inputMode == .text)
        #expect(appModel.textPrompt == "")
        #expect(appModel.selectedArtStyle == .realistic)
        #expect(appModel.selectedImageData == nil)
        #expect(appModel.generatedModelURL == nil)
        #expect(appModel.generatedModelData == nil)
        #expect(appModel.modelURLs == nil)
        #expect(appModel.immersiveSpaceState == .closed)
    }

    @Test func resetGeneration() {
        let appModel = AppModel()

        // Set some state
        appModel.generationPhase = .complete
        appModel.currentProgress = 100
        appModel.textPrompt = "Test prompt"
        appModel.selectedImageData = Data([0x00, 0x01])
        appModel.generatedModelURL = URL(fileURLWithPath: "/tmp/test.usdz")
        appModel.generatedModelData = Data([0x02, 0x03])

        // Reset
        appModel.resetGeneration()

        // Verify reset
        #expect(appModel.generationPhase == .idle)
        #expect(appModel.currentProgress == 0)
        #expect(appModel.textPrompt == "")
        #expect(appModel.selectedImageData == nil)
        #expect(appModel.generatedModelURL == nil)
        #expect(appModel.generatedModelData == nil)
        #expect(appModel.modelURLs == nil)
    }

    @Test func cancelGeneration() {
        let appModel = AppModel()

        appModel.generationPhase = .generatingPreview
        appModel.currentProgress = 50

        appModel.cancelGeneration()

        #expect(appModel.generationPhase == .idle)
        #expect(appModel.currentProgress == 0)
        #expect(appModel.activeGenerationTask == nil)
    }

    @Test func emptyPromptDoesNotStartGeneration() {
        let appModel = AppModel()

        appModel.textPrompt = ""
        appModel.startTextToGeneration()

        #expect(appModel.generationPhase == .idle)
    }

    @Test func whitespaceOnlyPromptDoesNotStartGeneration() {
        let appModel = AppModel()

        appModel.textPrompt = "   \n\t  "
        appModel.startTextToGeneration()

        #expect(appModel.generationPhase == .idle)
    }

    @Test func validPromptStartsGeneration() {
        let appModel = AppModel()

        appModel.textPrompt = "A red sports car"
        appModel.startTextToGeneration()

        #expect(appModel.generationPhase == .generatingPreview)
        #expect(appModel.currentProgress == 0)
        #expect(appModel.activeGenerationTask != nil)

        // Clean up
        appModel.cancelGeneration()
    }

    @Test func imageGenerationStarts() {
        let appModel = AppModel()

        appModel.startImageToGeneration(imageUrl: "https://example.com/image.jpg")

        #expect(appModel.generationPhase == .generatingFinal)
        #expect(appModel.currentProgress == 0)
        #expect(appModel.activeGenerationTask != nil)

        // Clean up
        appModel.cancelGeneration()
    }

    @Test func generationPhaseEquality() {
        #expect(AppModel.GenerationPhase.idle == AppModel.GenerationPhase.idle)
        #expect(AppModel.GenerationPhase.generatingPreview == AppModel.GenerationPhase.generatingPreview)
        #expect(AppModel.GenerationPhase.generatingFinal == AppModel.GenerationPhase.generatingFinal)
        #expect(AppModel.GenerationPhase.complete == AppModel.GenerationPhase.complete)
        #expect(AppModel.GenerationPhase.previewReady(taskId: "123") == AppModel.GenerationPhase.previewReady(taskId: "123"))
        #expect(AppModel.GenerationPhase.previewReady(taskId: "123") != AppModel.GenerationPhase.previewReady(taskId: "456"))
        #expect(AppModel.GenerationPhase.failed("error1") == AppModel.GenerationPhase.failed("error1"))
        #expect(AppModel.GenerationPhase.failed("error1") != AppModel.GenerationPhase.failed("error2"))
        #expect(AppModel.GenerationPhase.idle != AppModel.GenerationPhase.complete)
    }

    @Test func immersiveSpaceStates() {
        let appModel = AppModel()

        #expect(appModel.immersiveSpaceState == .closed)

        appModel.immersiveSpaceState = .inTransition
        #expect(appModel.immersiveSpaceState == .inTransition)

        appModel.immersiveSpaceState = .open
        #expect(appModel.immersiveSpaceState == .open)
    }

    @Test func inputModeToggle() {
        let appModel = AppModel()

        #expect(appModel.inputMode == .text)

        appModel.inputMode = .image
        #expect(appModel.inputMode == .image)

        appModel.inputMode = .text
        #expect(appModel.inputMode == .text)
    }

    @Test func artStyleSelection() {
        let appModel = AppModel()

        #expect(appModel.selectedArtStyle == .realistic)

        appModel.selectedArtStyle = .cartoon
        #expect(appModel.selectedArtStyle == .cartoon)

        appModel.selectedArtStyle = .lowPoly
        #expect(appModel.selectedArtStyle == .lowPoly)
    }
}

// MARK: - TaskCreateResponse Tests

struct TaskCreateResponseTests {

    @Test func taskCreateResponseDecoding() throws {
        let json = """
        {
            "result": "task-abc-123"
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(TaskCreateResponse.self, from: json.data(using: .utf8)!)

        #expect(response.result == "task-abc-123")
    }
}

// MARK: - ModelURLs Tests

struct ModelURLsTests {

    @Test func modelURLsFullDecoding() throws {
        let json = """
        {
            "glb": "https://example.com/model.glb",
            "fbx": "https://example.com/model.fbx",
            "obj": "https://example.com/model.obj",
            "mtl": "https://example.com/model.mtl",
            "usdz": "https://example.com/model.usdz"
        }
        """

        let decoder = JSONDecoder()
        let urls = try decoder.decode(ModelURLs.self, from: json.data(using: .utf8)!)

        #expect(urls.glb == "https://example.com/model.glb")
        #expect(urls.fbx == "https://example.com/model.fbx")
        #expect(urls.obj == "https://example.com/model.obj")
        #expect(urls.mtl == "https://example.com/model.mtl")
        #expect(urls.usdz == "https://example.com/model.usdz")
    }

    @Test func modelURLsPartialDecoding() throws {
        let json = """
        {
            "glb": "https://example.com/model.glb",
            "usdz": "https://example.com/model.usdz"
        }
        """

        let decoder = JSONDecoder()
        let urls = try decoder.decode(ModelURLs.self, from: json.data(using: .utf8)!)

        #expect(urls.glb == "https://example.com/model.glb")
        #expect(urls.usdz == "https://example.com/model.usdz")
        #expect(urls.fbx == nil)
        #expect(urls.obj == nil)
        #expect(urls.mtl == nil)
    }
}
