# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GenModel is a Vision Pro (visionOS) application that generates 3D models from text descriptions or images using the Replicate API. Generated models can be viewed in immersive space and exported to Files in USDZ, GLB, or OBJ formats.

## Build Commands

```bash
# Build the project
xcodebuild -project GenModel.xcodeproj -scheme GenModel -destination 'platform=visionOS Simulator,name=Apple Vision Pro'

# Run tests
xcodebuild test -project GenModel.xcodeproj -scheme GenModelTests -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

Note: This project requires Xcode with visionOS SDK. The RealityKitContent package uses Reality Composer Pro for 3D asset editing.

## API Setup

Set your Replicate API token in `AppModel.swift`:
```swift
enum ReplicateConfig {
    static let apiToken = "YOUR_REPLICATE_API_TOKEN_HERE"
}
```
Get an API token from https://replicate.com/account/api-tokens

**Models Used:**
- **Text-to-3D**: Shap-E (OpenAI) - generates GLB format
- **Image-to-3D**: TripoSR - generates GLB format

**Cost**: Pay-per-use, approximately $0.01-0.05 per generation (no subscription required)

## Architecture

### State Management
- `AppModel` is an `@Observable` class bound to `@MainActor` that manages:
  - Immersive space state (`closed`, `inTransition`, `open`)
  - Generation phase (`idle`, `generatingPreview`, `generatingFinal`, `complete`, `failed`)
  - User input (text prompt, art style, selected image)
  - Generated model data and URLs

### File Structure
```
GenModel/
├── Services/
│   ├── ReplicateAPIClient.swift # Replicate API networking (actor)
│   ├── ReplicateModels.swift    # Replicate request/response types
│   ├── MeshyAPIClient.swift     # Meshy API (legacy, unused)
│   └── MeshyModels.swift        # Shared types (ArtStyle, ExportFormat, ModelURLs)
├── Views/
│   ├── GenerationView.swift     # Main generation flow orchestrator
│   ├── TextInputView.swift      # Text prompt + art style picker
│   ├── ImageInputView.swift     # PhotosPicker + URL input
│   ├── GenerationProgressView.swift  # Progress circle during generation
│   └── ExportView.swift         # Format picker + file export
├── AppModel.swift               # Central state + generation logic
├── ContentView.swift            # Entry point (hosts GenerationView)
└── ImmersiveView.swift          # Loads generated model in immersive space
```

### Generation Flow
1. User enters text prompt OR provides image URL
2. `AppModel.startTextToGeneration()` or `startImageToGeneration()` called
3. Replicate API creates prediction, polls until complete
4. GLB model downloaded and saved to temp directory
5. Model displayed via `Model3D` in completed view
6. User can view in immersive space or export

### Key Patterns
- `ReplicateAPIClient` is an `actor` for thread-safe API calls
- Generation uses async polling with exponential backoff
- `Task` cancellation supported throughout generation flow
- `fileExporter` modifier for export to Files app

## Platform Requirements

- visionOS 2.0+
- Swift 6.0 (for packages)
- Xcode with Reality Composer Pro support
- Replicate API token (pay-per-use, no subscription required)
