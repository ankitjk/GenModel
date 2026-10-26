//
//  ImageInputView.swift
//  GenModel
//
//  Created by Claude Code on 23/12/25.
//

import SwiftUI
import PhotosUI

struct ImageInputView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedItem: PhotosPickerItem?
    @State private var imageUrlString: String = ""
    @State private var inputMode: ImageInputMode = .photo

    enum ImageInputMode {
        case photo
        case url
    }

    private var canGenerate: Bool {
        switch inputMode {
        case .photo:
            return appModel.selectedImageData != nil
        case .url:
            return !imageUrlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 24) {
            Text("Image to 3D")
                .font(.title)
                .fontWeight(.semibold)

            Text("Generate a 3D model from an image")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Input mode picker
            Picker("Input Method", selection: $inputMode) {
                Label("Photo Library", systemImage: "photo").tag(ImageInputMode.photo)
                Label("Image URL", systemImage: "link").tag(ImageInputMode.url)
            }
            .pickerStyle(.segmented)

            switch inputMode {
            case .photo:
                photoInputSection

            case .url:
                urlInputSection
            }

            Spacer()

            Button(action: startGeneration) {
                Label("Generate 3D Model", systemImage: "cube.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canGenerate)
        }
        .padding()
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    appModel.selectedImageData = data
                }
            }
        }
        .onChange(of: inputMode) { _, _ in
            // Clear the other input when switching modes
            if inputMode == .photo {
                imageUrlString = ""
            } else {
                appModel.selectedImageData = nil
                selectedItem = nil
            }
        }
    }

    // MARK: - Photo Input Section

    @ViewBuilder
    private var photoInputSection: some View {
        if let imageData = appModel.selectedImageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Button(role: .destructive) {
                appModel.selectedImageData = nil
                selectedItem = nil
            } label: {
                Label("Remove Image", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        } else {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Select an Image")
                        .font(.headline)

                    Text("Choose from your photo library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - URL Input Section

    @ViewBuilder
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter a publicly accessible image URL")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("https://example.com/image.jpg", text: $imageUrlString)
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)
                .autocapitalization(.none)

            if !imageUrlString.isEmpty {
                // Show a preview hint
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("URL entered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func startGeneration() {
        switch inputMode {
        case .photo:
            if let imageData = appModel.selectedImageData {
                appModel.startImageToGeneration(imageData: imageData)
            }
        case .url:
            let trimmedUrl = imageUrlString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedUrl.isEmpty {
                appModel.startImageToGeneration(imageUrl: trimmedUrl)
            }
        }
    }
}

#Preview {
    ImageInputView()
        .environment(AppModel())
}
