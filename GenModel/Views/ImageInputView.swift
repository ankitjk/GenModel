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
    @State private var showUrlInput: Bool = false

    var body: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 24) {
            Text("Image to 3D")
                .font(.title)
                .fontWeight(.semibold)

            Text("Generate a 3D model from an image")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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

            Divider()

            // URL Input option (Meshy requires a publicly accessible URL)
            VStack(alignment: .leading, spacing: 8) {
                Text("Or enter image URL")
                    .font(.headline)

                Text("Meshy requires a publicly accessible image URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("https://example.com/image.jpg", text: $imageUrlString)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .autocapitalization(.none)
            }

            Spacer()

            Button(action: {
                if !imageUrlString.isEmpty {
                    appModel.startImageToGeneration(imageUrl: imageUrlString)
                }
            }) {
                Label("Generate 3D Model", systemImage: "cube.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(imageUrlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    appModel.selectedImageData = data
                }
            }
        }
    }
}

#Preview {
    ImageInputView()
        .environment(AppModel())
}
