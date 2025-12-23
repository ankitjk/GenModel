//
//  GenerationView.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import SwiftUI
import RealityKit

struct GenerationView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showExportSheet = false

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            Group {
                switch appModel.generationPhase {
                case .idle:
                    inputView

                case .generatingPreview, .previewReady, .generatingFinal:
                    GenerationProgressView()

                case .complete:
                    completedView

                case .failed(let error):
                    errorView(error: error)
                }
            }
            .navigationTitle("Generate 3D Model")
            .toolbar {
                if appModel.generationPhase == .complete {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New") {
                            appModel.resetGeneration()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportView()
        }
    }

    // MARK: - Input View

    @ViewBuilder
    private var inputView: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 20) {
            Picker("Input Mode", selection: $appModel.inputMode) {
                Label("Text", systemImage: "text.cursor").tag(AppModel.InputMode.text)
                Label("Image", systemImage: "photo").tag(AppModel.InputMode.image)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch appModel.inputMode {
            case .text:
                TextInputView()
            case .image:
                ImageInputView()
            }
        }
    }

    // MARK: - Completed View

    @ViewBuilder
    private var completedView: some View {
        VStack(spacing: 24) {
            if let modelURL = appModel.generatedModelURL {
                Model3D(url: modelURL) { model in
                    model
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 300)
            }

            Text("Generation Complete!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your 3D model is ready to view and export.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    showExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)

                ToggleImmersiveSpaceButton()
            }
            .padding(.horizontal)

            Button(role: .destructive) {
                appModel.resetGeneration()
            } label: {
                Label("Generate Another", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Generation Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                appModel.generationPhase = .idle
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    GenerationView()
        .environment(AppModel())
}
