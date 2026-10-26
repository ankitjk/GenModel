# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GenModel is a Vision Pro (visionOS) application that generates 3D models from text descriptions or images using the Replicate API. Generated models (GLB) can be previewed in-window, viewed in an immersive space, and saved to the Files app.

## Build Commands

```bash
# Build the project
xcodebuild -project GenModel.xcodeproj -scheme GenModel -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build

# Run tests (the GenModel scheme includes the GenModelTests target; tests use Swift Testing)
xcodebuild test -project GenModel.xcodeproj -scheme GenModel -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

Notes:
- Requires Xcode 16.4+ with the visionOS 2.5 SDK (deployment target is 2.5). If `xcodebuild` reports a simulator clone failure, pass an existing device by `id=` and `-parallel-testing-enabled NO`.
- The project uses Xcode 16 synchronized folders: files added to `GenModel/` or `GenModelTests/` on disk are picked up without editing `project.pbxproj`.
- The RealityKitContent package uses Reality Composer Pro for 3D asset editing.

## API Setup

The Replicate token is read at launch from `GenModel/Secrets.plist` (git-ignored) by `ReplicateConfig.apiToken` in `AppModel.swift`:

```bash
cp Secrets.example.plist GenModel/Secrets.plist   # then paste the token
```

Get a token from https://replicate.com/account/api-tokens. Never hardcode it in source.

**Models Used:**
- **Text-to-3D**: Shap-E (OpenAI, `cjwbw/shap-e`) - outputs GLB
- **Image-to-3D**: TRELLIS (`firtoz/trellis`) - outputs textured GLB; accepts a URL or a base64 data URI

**Cost**: Pay-per-use, approximately $0.01-0.05 per generation (no subscription required)

## Architecture

### State Management
- `AppModel` is an `@Observable` class bound to `@MainActor` that manages:
  - Immersive space state (`closed`, `inTransition`, `open`)
  - Generation phase (`idle`, `generatingPreview`, `generatingFinal`, `complete`, `failed`); Replicate flows go straight to `generatingFinal`
  - User input (text prompt, art style, selected image)
  - Generated model data and URLs

### File Structure
```
GenModel/
├── Services/
│   ├── ReplicateAPIClient.swift # Replicate API networking (actor), polling, download
│   ├── ReplicateModels.swift    # Replicate request/response types + ReplicateAPIError
│   ├── ModelLoader.swift        # Multi-format loader -> RealityKit Entity (GLTFKit2, ModelIO)
│   └── MeshyModels.swift        # Shared types (ArtStyle, ExportFormat, ModelURLs); legacy Meshy types kept for tests
├── Views/
│   ├── GenerationView.swift     # Main generation flow orchestrator + Model3D preview
│   ├── TextInputView.swift      # Text prompt + art style picker
│   ├── ImageInputView.swift     # PhotosPicker + URL input
│   ├── GenerationProgressView.swift  # Progress circle during generation
│   └── ExportView.swift         # Saves the generated file to the app's Documents folder (visible in Files)
├── AppModel.swift               # Central state + generation logic + ReplicateConfig
├── ContentView.swift            # Entry point (hosts GenerationView)
└── ImmersiveView.swift          # Loads generated model in immersive space via ModelLoader
```

### Generation Flow
1. User enters text prompt OR picks a photo / provides an image URL
2. `AppModel.startTextToGeneration()` or `startImageToGeneration(...)` called
3. Replicate API creates prediction, polls until complete (1s start, x1.2 backoff, 5s cap, 300 attempts)
4. GLB model downloaded and saved to temp directory
5. Model displayed via `Model3D` in completed view
6. User can view in immersive space (auto-scaled, placed in front of user) or save to Files

### Key Patterns
- `ReplicateAPIClient` is an `actor` for thread-safe API calls; it throws `ReplicateAPIError.missingAPIToken` if no token is configured
- Generation uses async polling with exponential backoff
- `Task` cancellation supported throughout generation flow
- Export is a plain write to the Documents directory; `Info.plist` sets `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` so it appears in Files

## Platform Requirements

- visionOS 2.5+
- Xcode 16.4+ with Reality Composer Pro support
- Swift package: GLTFKit2 (resolved automatically; lock in `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`)
- Replicate API token (pay-per-use, no subscription required)
