import PhotosUI
import SwiftUI
import UIKit

struct ContainerEditorView: View {
    @EnvironmentObject private var store: StorageViewModel
    @Environment(\.dismiss) private var dismiss

    private let container: StorageContainer?
    private let parentID: UUID?

    @State private var name: String
    @State private var details: String
    @State private var photoKey: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var cropRequest: PhotoCropRequest?
    @State private var isShowingCamera = false
    @State private var selectedTagIDs: Set<UUID>
    @State private var isShowingTagPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(container: StorageContainer? = nil, parentID: UUID?) {
        self.container = container
        self.parentID = parentID
        _name = State(initialValue: container?.name ?? "")
        _details = State(initialValue: container?.details ?? "")
        _photoKey = State(initialValue: container?.photoKey)
        _selectedTagIDs = State(initialValue: container?.tagIds ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Фото") {
                    photoPreview

                    Button {
                        if CameraCaptureView.isAvailable {
                            isShowingCamera = true
                        } else {
                            errorMessage = "Камера недоступна на этом устройстве."
                        }
                    } label: {
                        Label("Сфотографировать", systemImage: "camera")
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label {
                            Text("Выбрать фото")
                        } icon: {
                            Image(systemName: "photo.on.rectangle")
                        }
                    }

                    if photoKey != nil || selectedPhotoData != nil {
                        Button("Удалить фото", role: .destructive) {
                            selectedPhotoData = nil
                            selectedPhotoItem = nil
                            photoKey = nil
                        }
                    }
                }

                Section("Контейнер") {
                    TextField("Название", text: $name)
                        .textInputAutocapitalization(.sentences)

                    TextField("Заметка", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Теги") {
                    selectedTagsView

                    Button {
                        isShowingTagPicker = true
                    } label: {
                        Label("Добавить тег", systemImage: "tag")
                    }
                }
            }
            .navigationTitle(container == nil ? "Новый контейнер" : "Контейнер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Сохранение" : "Сохранить") {
                        Task { await save() }
                    }
                    .disabled(trimmedName.isEmpty || isSaving)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadPhoto(from: newItem)
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    cropRequest = PhotoCropRequest(image: image)
                }
            }
            .sheet(item: $cropRequest) { request in
                SquarePhotoCropEditorView(sourceImage: request.image) { croppedData in
                    selectedPhotoData = croppedData
                    photoKey = nil
                }
            }
            .sheet(isPresented: $isShowingTagPicker) {
                NavigationStack {
                    TagHierarchyView(mode: .selection, selectedTagIDs: $selectedTagIDs)
                }
            }
            .alert("Не удалось сохранить", isPresented: hasErrorMessage) {
                Button("ОК", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var photoPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.12))

            if let selectedPhotoData,
               let image = UIImage(data: selectedPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(1)
            } else if photoKey != nil {
                RemotePhotoView(photoKey: photoKey, placeholderSystemName: "shippingbox.fill", contentMode: .fit)
                    .padding(1)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 34, weight: .semibold))
                    Text("Фото контейнера")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private var selectedTagsView: some View {
        let selectedTags = TagUtilities.selectedTags(tagIDs: selectedTagIDs, allTags: store.tags)

        return Group {
            if selectedTags.isEmpty {
                Text("Теги не добавлены")
                    .foregroundStyle(.secondary)
            } else {
                TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(selectedTags) { tag in
                        TagChipView(
                            title: TagUtilities.displayName(tag),
                            onTap: {
                                isShowingTagPicker = true
                            },
                            onRemove: {
                                selectedTagIDs.remove(tag.id)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDetails: String {
        details.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasErrorMessage: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else {
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw ContainerPhotoLoadingError.invalidImage
            }

            await MainActor.run {
                cropRequest = PhotoCropRequest(image: image)
                selectedPhotoItem = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            if let container {
                try await store.updateContainer(
                    container,
                    name: trimmedName,
                    details: trimmedDetails,
                    photoData: selectedPhotoData,
                    removePhoto: photoKey == nil && container.photoKey != nil && selectedPhotoData == nil,
                    tagIDs: selectedTagIDs
                )
            } else {
                try await store.createContainer(
                    name: trimmedName,
                    details: trimmedDetails,
                    parentID: parentID,
                    photoData: selectedPhotoData,
                    tagIDs: selectedTagIDs
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ContainerPhotoLoadingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Не удалось открыть изображение."
    }
}
