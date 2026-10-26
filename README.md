# GenModel

Text- and image-to-3D on Apple Vision Pro. Describe an object or pick a photo, get a 3D model back from a hosted ML model, inspect it in an immersive space, and save it to Files.

Built with Swift, SwiftUI and RealityKit on visionOS. Generation runs on [Replicate](https://replicate.com) (pay-per-use, roughly $0.01–0.05 per model, no subscription).

## What it does

- **Text → 3D** with OpenAI's [Shap-E](https://replicate.com/cjwbw/shap-e), with an art-style picker (realistic, cartoon, low-poly, sculpture, PBR) that shapes the prompt.
- **Image → 3D** with Microsoft's [TRELLIS](https://replicate.com/firtoz/trellis), from a photo in your library (uploaded as a data URI) or a public image URL. Produces a textured GLB.
- **Preview** the result in-window with `Model3D`, then open it in an **immersive space** where it is auto-scaled from its bounds and placed in front of you.
- **Save to Files**: the generated model is written to the app's Documents folder, which is exposed to the Files app.
- **Cancel** at any point; the in-flight prediction and download are torn down via Swift `Task` cancellation.

## How it works

```
TextInputView / ImageInputView
        │  prompt or image
        ▼
AppModel (@MainActor, @Observable)      ── generation phase, progress, cancellation
        │
        ▼
ReplicateAPIClient (actor)              ── POST /predictions, then poll GET /predictions/{id}
        │  GLB bytes
        ▼
ModelLoader                              ── GLB/glTF via GLTFKit2 · USDZ via RealityKit · OBJ/PLY/STL via ModelIO
        │  RealityKit Entity
        ▼
GenerationView (Model3D)  ·  ImmersiveView (RealityView)  ·  ExportView (Files)
```

- **Polling with backoff.** Replicate predictions are asynchronous. The client polls starting at 1 s, multiplying the interval by 1.2 up to a 5 s cap, for at most 300 attempts (~10 minutes), mapping the prediction status to a progress estimate and checking for cancellation on every loop.
- **Thread safety.** `ReplicateAPIClient` is a Swift `actor`; all UI state lives in a `@MainActor` `AppModel`.
- **Multi-format loading.** `ModelLoader` normalizes USDZ, GLB/glTF, OBJ, PLY and STL into RealityKit entities. For ModelIO-backed formats it reads the vertex and index buffers directly and rebuilds a `MeshResource`, so the immersive view does not depend on RealityKit's native importer for every format.

## Project layout

```
GenModel/
├── AppModel.swift                  # App state + generation orchestration
├── ContentView.swift               # Entry point
├── ImmersiveView.swift             # Loads the model into the immersive space
├── Services/
│   ├── ReplicateAPIClient.swift    # Replicate networking (actor), polling, download
│   ├── ReplicateModels.swift       # Request/response types, errors
│   ├── ModelLoader.swift           # Multi-format → RealityKit Entity
│   └── MeshyModels.swift           # Shared enums (ArtStyle, ExportFormat, ModelURLs)
└── Views/
    ├── GenerationView.swift        # Flow orchestrator + Model3D preview
    ├── TextInputView.swift         # Prompt + art style
    ├── ImageInputView.swift        # PhotosPicker + URL input
    ├── GenerationProgressView.swift
    └── ExportView.swift            # Save to Files
GenModelTests/                      # 28 Swift Testing tests (models, state machine, decoding)
Packages/RealityKitContent/         # Reality Composer Pro package
```

## Running it

**Requirements:** Xcode 16.4+ with the visionOS 2.5 SDK, an Apple Vision Pro or the simulator, and a Replicate API token.

1. Clone the repo and open `GenModel.xcodeproj`. Xcode resolves the one package dependency ([GLTFKit2](https://github.com/warrenm/GLTFKit2)) automatically.
2. Add your token. Copy the example file and paste a token from <https://replicate.com/account/api-tokens>:
   ```bash
   cp Secrets.example.plist GenModel/Secrets.plist
   ```
   `GenModel/Secrets.plist` is git-ignored. Without it the app builds and runs, and generation fails with a clear "no token configured" error.
3. Build and run on the Apple Vision Pro simulator, or from the command line:
   ```bash
   xcodebuild -project GenModel.xcodeproj -scheme GenModel \
     -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build
   ```

**Tests:**
```bash
xcodebuild test -project GenModel.xcodeproj -scheme GenModel \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

## Status and known limitations

- Shap-E's text-to-3D output is low-fidelity by today's standards; TRELLIS (image-to-3D) is noticeably better. Swapping the text model is a one-line change to the Replicate version ID in `ReplicateAPIClient`.
- Export writes the GLB as generated; there is no in-app conversion to other formats yet.
- Generation typically takes 30–90 s depending on model cold starts on Replicate.
