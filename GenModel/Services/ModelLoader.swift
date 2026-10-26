//
//  ModelLoader.swift
//  GenModel
//
//  Created by Claude Code on 24/12/25.
//

import RealityKit
import ModelIO
import MetalKit
import GLTFKit2
import os.log

private let logger = Logger(subsystem: "com.genmodel", category: "ModelLoader")

/// Error types for model loading
enum ModelLoaderError: LocalizedError {
    case unsupportedFormat(String)
    case noMeshFound
    case metalDeviceUnavailable
    case meshConversionFailed(String)
    case vertexDataExtractionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported 3D format: \(format)"
        case .noMeshFound:
            return "No mesh data found in file"
        case .metalDeviceUnavailable:
            return "Metal device not available"
        case .meshConversionFailed(let reason):
            return "Failed to convert mesh: \(reason)"
        case .vertexDataExtractionFailed:
            return "Failed to extract vertex data from mesh"
        }
    }
}

/// Unified model loader supporting multiple 3D formats
enum ModelLoader {

    /// Load a 3D model from URL, supporting multiple formats
    /// - Parameter url: File URL of the 3D model
    /// - Returns: A RealityKit Entity containing the loaded model
    static func loadEntity(from url: URL) async throws -> Entity {
        let ext = url.pathExtension.lowercased()
        logger.info("Loading model with extension: \(ext) from \(url.lastPathComponent)")

        switch ext {
        case "usdz", "usda", "usdc", "reality":
            // Native RealityKit support
            logger.info("Using native RealityKit loader for \(ext)")
            return try await Entity(contentsOf: url)

        case "obj":
            // Use ModelIO for OBJ files
            logger.info("Using ModelIO loader for OBJ")
            return try await loadWithModelIO(from: url)

        case "ply":
            // Use ModelIO for PLY files
            logger.info("Using ModelIO loader for PLY")
            return try await loadWithModelIO(from: url)

        case "glb", "gltf":
            // Use GLTFKit2 for GLB/GLTF files
            logger.info("Using GLTFKit2 loader for GLB/GLTF")
            return try await loadWithGLTFKit2(from: url)

        case "stl":
            // Use ModelIO for STL files
            logger.info("Using ModelIO loader for STL")
            return try await loadWithModelIO(from: url)

        default:
            // Try ModelIO as a generic fallback
            logger.warning("Unknown format '\(ext)', trying ModelIO")
            return try await loadWithModelIO(from: url)
        }
    }

    // MARK: - GLTFKit2 Loading (for GLB/GLTF)

    private static func loadWithGLTFKit2(from url: URL) async throws -> Entity {
        logger.info("Loading GLB/GLTF with GLTFKit2 from \(url.lastPathComponent)")

        // GLTFRealityKitLoader.load(from:) is the main entry point for converting
        // glTF assets to RealityKit entities. It handles meshes, materials,
        // animations, and skeletal data.
        let entity = try await GLTFRealityKitLoader.load(from: url)

        logger.info("Successfully loaded GLB/GLTF via GLTFKit2")
        return entity
    }

    // MARK: - Generic ModelIO Loading

    private static func loadWithModelIO(from url: URL) async throws -> Entity {
        // Extract mesh data on background thread
        let meshDataArray = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[MeshData], Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try extractMeshData(from: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Create RealityKit entities on main actor
        return try await createEntities(from: meshDataArray)
    }

    /// Intermediate data structure to pass mesh data between threads
    private struct MeshData {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let textureCoords: [SIMD2<Float>]
        let indices: [UInt32]
    }

    /// Extract mesh data from file (can run on background thread)
    private static func extractMeshData(from url: URL) throws -> [MeshData] {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ModelLoaderError.metalDeviceUnavailable
        }

        let allocator = MTKMeshBufferAllocator(device: device)

        // Load asset WITHOUT imposing a vertex descriptor - let ModelIO use native format
        let asset = MDLAsset(url: url,
                             vertexDescriptor: nil,
                             bufferAllocator: allocator)

        logger.info("ModelIO load, object count: \(asset.count)")

        // Collect all meshes from the asset hierarchy
        var meshes: [MDLMesh] = []

        func collectMeshes(from object: MDLObject) {
            if let mesh = object as? MDLMesh {
                meshes.append(mesh)
            }
            for child in object.children.objects {
                collectMeshes(from: child)
            }
        }

        for i in 0..<asset.count {
            let object = asset.object(at: i)
            collectMeshes(from: object)
        }

        if meshes.isEmpty {
            logger.error("No meshes found in file")
            throw ModelLoaderError.noMeshFound
        }

        logger.info("Found \(meshes.count) mesh(es)")

        var meshDataArray: [MeshData] = []

        for (index, mdlMesh) in meshes.enumerated() {
            logger.info("Processing mesh \(index): \(mdlMesh.vertexCount) vertices")

            do {
                // Add normals if they don't exist
                if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                    mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.7)
                    logger.info("Generated normals for mesh \(index)")
                }

                let data = try extractVertexData(from: mdlMesh)
                meshDataArray.append(data)
                logger.info("Successfully extracted data for mesh \(index)")

            } catch {
                logger.error("Failed to extract mesh \(index): \(error.localizedDescription)")
            }
        }

        if meshDataArray.isEmpty {
            throw ModelLoaderError.meshConversionFailed("No meshes could be extracted")
        }

        return meshDataArray
    }

    /// Create RealityKit entities from mesh data (must run on main actor)
    @MainActor
    private static func createEntities(from meshDataArray: [MeshData]) throws -> Entity {
        let parentEntity = Entity()
        var successCount = 0

        for (index, data) in meshDataArray.enumerated() {
            do {
                // Build mesh descriptor
                var meshDescriptor = MeshDescriptor(name: "mesh_\(index)")
                meshDescriptor.positions = MeshBuffer(data.positions)
                meshDescriptor.normals = MeshBuffer(data.normals)
                meshDescriptor.textureCoordinates = MeshBuffer(data.textureCoords)
                meshDescriptor.primitives = .triangles(data.indices)

                let meshResource = try MeshResource.generate(from: [meshDescriptor])

                // Create material
                var material = SimpleMaterial()
                material.color = .init(tint: .white)
                material.roughness = .init(floatLiteral: 0.5)
                material.metallic = .init(floatLiteral: 0.0)

                let modelEntity = ModelEntity(mesh: meshResource, materials: [material])
                parentEntity.addChild(modelEntity)
                successCount += 1

                logger.info("Successfully created ModelEntity for mesh \(index)")

            } catch {
                logger.error("Failed to create entity for mesh \(index): \(error.localizedDescription)")
            }
        }

        if parentEntity.children.isEmpty {
            throw ModelLoaderError.meshConversionFailed("No entities could be created")
        }

        logger.info("Successfully created \(successCount)/\(meshDataArray.count) entities")
        return parentEntity
    }

    /// Extract vertex data from MDLMesh (can run on background thread)
    private static func extractVertexData(from mdlMesh: MDLMesh) throws -> MeshData {
        let vertexCount = mdlMesh.vertexCount

        guard vertexCount > 0 else {
            throw ModelLoaderError.vertexDataExtractionFailed
        }

        logger.info("Converting mesh with \(vertexCount) vertices")

        // Extract positions from vertex buffers directly
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var textureCoords: [SIMD2<Float>] = []

        // Get vertex descriptor to understand layout
        let descriptor = mdlMesh.vertexDescriptor

        // Find position attribute
        var positionOffset = 0
        var positionBufferIndex = 0
        var normalOffset = -1
        var normalBufferIndex = 0
        var uvOffset = -1
        var uvBufferIndex = 0

        for i in 0..<descriptor.attributes.count {
            guard let attr = descriptor.attributes[i] as? MDLVertexAttribute else { continue }

            if attr.name == MDLVertexAttributePosition {
                positionOffset = attr.offset
                positionBufferIndex = attr.bufferIndex
                logger.info("Position: buffer \(positionBufferIndex), offset \(positionOffset)")
            } else if attr.name == MDLVertexAttributeNormal {
                normalOffset = attr.offset
                normalBufferIndex = attr.bufferIndex
                logger.info("Normal: buffer \(normalBufferIndex), offset \(normalOffset)")
            } else if attr.name == MDLVertexAttributeTextureCoordinate {
                uvOffset = attr.offset
                uvBufferIndex = attr.bufferIndex
                logger.info("UV: buffer \(uvBufferIndex), offset \(uvOffset)")
            }
        }

        // Get buffer layouts (strides)
        guard let positionLayout = descriptor.layouts[positionBufferIndex] as? MDLVertexBufferLayout else {
            throw ModelLoaderError.vertexDataExtractionFailed
        }
        let positionStride = positionLayout.stride
        logger.info("Position stride: \(positionStride)")

        // Get vertex buffer data
        guard positionBufferIndex < mdlMesh.vertexBuffers.count else {
            throw ModelLoaderError.vertexDataExtractionFailed
        }

        let positionBuffer = mdlMesh.vertexBuffers[positionBufferIndex]

        // Map the buffer and extract data
        let positionMap = positionBuffer.map()
        let positionBytes = positionMap.bytes

        for i in 0..<vertexCount {
            let vertexStart = i * positionStride + positionOffset
            let ptr = positionBytes.advanced(by: vertexStart).assumingMemoryBound(to: Float.self)
            positions.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
        }

        logger.info("Extracted \(positions.count) positions")

        // Extract normals if available
        if normalOffset >= 0 && normalBufferIndex < mdlMesh.vertexBuffers.count {
            let normalBuffer = mdlMesh.vertexBuffers[normalBufferIndex]
            if let normalLayout = descriptor.layouts[normalBufferIndex] as? MDLVertexBufferLayout {
                let normalMap = normalBuffer.map()
                let normalStride = normalLayout.stride
                let normalBytes = normalMap.bytes

                for i in 0..<vertexCount {
                    let vertexStart = i * normalStride + normalOffset
                    let ptr = normalBytes.advanced(by: vertexStart).assumingMemoryBound(to: Float.self)
                    normals.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
                }
                logger.info("Extracted \(normals.count) normals")
            }
        }

        // If no normals, generate default
        if normals.isEmpty {
            normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: vertexCount)
            logger.info("Using default normals")
        }

        // Extract UVs if available
        if uvOffset >= 0 && uvBufferIndex < mdlMesh.vertexBuffers.count {
            let uvBuffer = mdlMesh.vertexBuffers[uvBufferIndex]
            if let uvLayout = descriptor.layouts[uvBufferIndex] as? MDLVertexBufferLayout {
                let uvMap = uvBuffer.map()
                let uvStride = uvLayout.stride
                let uvBytes = uvMap.bytes

                for i in 0..<vertexCount {
                    let vertexStart = i * uvStride + uvOffset
                    let ptr = uvBytes.advanced(by: vertexStart).assumingMemoryBound(to: Float.self)
                    textureCoords.append(SIMD2<Float>(ptr[0], ptr[1]))
                }
                logger.info("Extracted \(textureCoords.count) UVs")
            }
        }

        // If no UVs, generate default
        if textureCoords.isEmpty {
            textureCoords = Array(repeating: SIMD2<Float>(0, 0), count: vertexCount)
        }

        // Extract indices from submeshes
        var allIndices: [UInt32] = []

        if let submeshes = mdlMesh.submeshes as? [MDLSubmesh] {
            logger.info("Found \(submeshes.count) submeshes")

            for (subIndex, submesh) in submeshes.enumerated() {
                let indexBuffer = submesh.indexBuffer
                let indexCount = submesh.indexCount

                logger.info("Submesh \(subIndex): \(indexCount) indices, type: \(submesh.indexType.rawValue)")

                // Map the index buffer
                let indexMap = indexBuffer.map()
                let indexBytes = indexMap.bytes

                switch submesh.indexType {
                case .uInt16:
                    let ptr = indexBytes.assumingMemoryBound(to: UInt16.self)
                    for i in 0..<indexCount {
                        allIndices.append(UInt32(ptr[i]))
                    }
                case .uInt32:
                    let ptr = indexBytes.assumingMemoryBound(to: UInt32.self)
                    for i in 0..<indexCount {
                        allIndices.append(ptr[i])
                    }
                case .uInt8:
                    let ptr = indexBytes.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<indexCount {
                        allIndices.append(UInt32(ptr[i]))
                    }
                case .invalid:
                    logger.warning("Invalid index type for submesh \(subIndex)")
                @unknown default:
                    logger.warning("Unknown index type for submesh \(subIndex)")
                }
            }
        }

        // If no indices found, create sequential indices
        if allIndices.isEmpty {
            logger.info("No indices found, creating sequential indices")
            for i in 0..<UInt32(vertexCount) {
                allIndices.append(i)
            }
        }

        // Validate indices
        let maxIndex = allIndices.max() ?? 0
        if maxIndex >= UInt32(vertexCount) {
            logger.warning("Invalid indices detected (max: \(maxIndex), vertices: \(vertexCount))")
            // Clamp indices to valid range
            allIndices = allIndices.map { min($0, UInt32(vertexCount - 1)) }
        }

        logger.info("Building mesh: \(positions.count) vertices, \(allIndices.count) indices")

        return MeshData(
            positions: positions,
            normals: normals,
            textureCoords: textureCoords,
            indices: allIndices
        )
    }

}
