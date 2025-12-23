# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GenModel is a Vision Pro (visionOS) application that generates 3D models from text descriptions or images using the Meshy.ai API. Generated models can be viewed in immersive space and exported to Files in USDZ, GLB, or OBJ formats.

## Build Commands

```bash
# Build the project
xcodebuild -project GenModel.xcodeproj -scheme GenModel -destination 'platform=visionOS Simulator,name=Apple Vision Pro'

# Run tests
xcodebuild test -project GenModel.xcodeproj -scheme GenModelTests -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

Note: This project requires Xcode with visionOS SDK. The RealityKitContent package uses Reality Composer Pro for 3D asset editing.

## API Setup

Set your Meshy API key in `AppModel.swift`:
```swift
enum MeshyConfig {
    static let apiKey = "YOUR_MESHY_API_KEY_HERE"
}
```
Get an API key from https://www.meshy.ai/

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
│   ├── MeshyAPIClient.swift     # Meshy API networking (actor)
│   └── MeshyModels.swift        # Request/response Codable types
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
3. API client creates task, polls until complete
4. USDZ downloaded and saved to temp directory
5. Model displayed via `Model3D` in completed view
6. User can view in immersive space or export

### Key Patterns
- `MeshyAPIClient` is an `actor` for thread-safe API calls
- Generation uses async polling with exponential backoff
- `Task` cancellation supported throughout generation flow
- `fileExporter` modifier for export to Files app

## Platform Requirements

- visionOS 2.0+
- Swift 6.0 (for packages)
- Xcode with Reality Composer Pro support
- Meshy.ai API key (Pro plan ~$20/month)
