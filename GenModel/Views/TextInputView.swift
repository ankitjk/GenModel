//
//  TextInputView.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import SwiftUI

struct TextInputView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 24) {
            Text("Text to 3D")
                .font(.title)
                .fontWeight(.semibold)

            Text("Describe the 3D model you want to generate")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.headline)

                TextField("A red sports car with chrome wheels...", text: $appModel.textPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Text("\(appModel.textPrompt.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Art Style")
                    .font(.headline)

                Picker("Art Style", selection: $appModel.selectedArtStyle) {
                    ForEach(ArtStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            Button(action: {
                appModel.startTextToGeneration()
            }) {
                Label("Generate 3D Model", systemImage: "cube.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.textPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }
}

#Preview {
    TextInputView()
        .environment(AppModel())
}
