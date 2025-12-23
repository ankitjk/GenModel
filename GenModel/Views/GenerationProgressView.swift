//
//  GenerationProgressView.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import SwiftUI

struct GenerationProgressView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(lineWidth: 8)
                    .foregroundStyle(.secondary.opacity(0.3))

                Circle()
                    .trim(from: 0, to: CGFloat(appModel.currentProgress) / 100)
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: appModel.currentProgress)

                VStack(spacing: 4) {
                    Text("\(appModel.currentProgress)%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))

                    Text(phaseText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            Text(statusMessage)
                .font(.headline)
                .multilineTextAlignment(.center)

            ProgressView()
                .progressViewStyle(.circular)

            Spacer()

            Button(role: .destructive) {
                appModel.cancelGeneration()
            } label: {
                Label("Cancel", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var phaseText: String {
        switch appModel.generationPhase {
        case .generatingPreview:
            return "Creating Preview"
        case .previewReady:
            return "Preview Ready"
        case .generatingFinal:
            return "Adding Textures"
        default:
            return "Processing"
        }
    }

    private var statusMessage: String {
        switch appModel.generationPhase {
        case .generatingPreview:
            return "Generating 3D geometry...\nThis may take 1-2 minutes."
        case .previewReady:
            return "Preview complete!\nNow adding textures..."
        case .generatingFinal:
            return "Applying materials and textures...\nAlmost done!"
        default:
            return "Processing your request..."
        }
    }
}

#Preview {
    GenerationProgressView()
        .environment(AppModel())
}
