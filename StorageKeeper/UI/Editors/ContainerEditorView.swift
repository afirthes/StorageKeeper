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
    @State private var photos: [PhotoDraftPayload]
    @State private var primaryPhotoID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
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
        let initialPhotos = container?.displayPhotoKeys.map { PhotoDraftPayload(photoKey: $0) } ?? []
        _photos = State(initialValue: initialPhotos)
        _primaryPhotoID = State(initialValue: initialPhotos.first { $0.photoKey == container?.primaryDisplayPhotoKey }?.id ?? initialPhotos.first?.id)
        _selectedTagIDs = State(initialValue: container?.tagIds ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Фото") {
                    EditablePhotoGalleryView(
                        photos: $photos,
                        primaryPhotoID: $primaryPhotoID,
                        placeholderSystemName: "shippingbox.fill"
                    )

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

                    if !photos.isEmpty {
                        Button("Удалить все фото", role: .destructive) {
                            photos = []
                            selectedPhotoItem = nil
                            primaryPhotoID = nil
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
                    appendPhoto(croppedData)
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
                    photos: photos,
                    primaryPhotoID: primaryPhotoID,
                    tagIDs: selectedTagIDs
                )
            } else {
                try await store.createContainer(
                    name: trimmedName,
                    details: trimmedDetails,
                    parentID: parentID,
                    photos: photos,
                    primaryPhotoID: primaryPhotoID,
                    tagIDs: selectedTagIDs
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendPhoto(_ data: Data) {
        let photo = PhotoDraftPayload(data: data)
        photos.append(photo)
        if primaryPhotoID == nil {
            primaryPhotoID = photo.id
        }
    }
}

private enum ContainerPhotoLoadingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Не удалось открыть изображение."
    }
}
