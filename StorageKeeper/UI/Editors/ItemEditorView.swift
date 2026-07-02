import PhotosUI
import SwiftUI
import UIKit

enum ItemEditorMode {
    case create(containerID: UUID?)
    case edit(StoredItem)
}

struct ItemEditorView: View {
    @EnvironmentObject private var store: StorageViewModel
    @Environment(\.dismiss) private var dismiss

    private let mode: ItemEditorMode

    @State private var name: String
    @State private var itemDescription: String
    @State private var photos: [PhotoDraftPayload]
    @State private var primaryPhotoID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cropRequest: PhotoCropRequest?
    @State private var isShowingCamera = false
    @State private var selectedTagIDs: Set<UUID>
    @State private var isShowingTagPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: ItemEditorMode) {
        self.mode = mode

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _itemDescription = State(initialValue: "")
            _photos = State(initialValue: [])
            _primaryPhotoID = State(initialValue: nil)
            _selectedTagIDs = State(initialValue: [])
        case .edit(let item):
            _name = State(initialValue: item.name)
            _itemDescription = State(initialValue: item.itemDescription)
            let initialPhotos = item.displayPhotoKeys.map { PhotoDraftPayload(photoKey: $0) }
            _photos = State(initialValue: initialPhotos)
            _primaryPhotoID = State(initialValue: initialPhotos.first { $0.photoKey == item.primaryDisplayPhotoKey }?.id ?? initialPhotos.first?.id)
            _selectedTagIDs = State(initialValue: item.tagIds)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Фото") {
                    EditablePhotoGalleryView(
                        photos: $photos,
                        primaryPhotoID: $primaryPhotoID,
                        placeholderSystemName: "photo"
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

                Section("Вещь") {
                    TextField("Название", text: $name)
                        .textInputAutocapitalization(.sentences)

                    TextField("Короткое описание", text: $itemDescription, axis: .vertical)
                        .lineLimit(3...7)
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
            .navigationTitle(title)
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

    private var title: String {
        switch mode {
        case .create:
            return "Новая вещь"
        case .edit:
            return "Вещь"
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

    private var trimmedDescription: String {
        itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
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
                throw PhotoLoadingError.invalidImage
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
            switch mode {
            case .create(let containerID):
                try await store.createItem(
                    name: trimmedName,
                    description: trimmedDescription,
                    containerID: containerID,
                    photos: photos,
                    primaryPhotoID: primaryPhotoID,
                    tagIDs: selectedTagIDs
                )

            case .edit(let item):
                try await store.updateItem(
                    item,
                    name: trimmedName,
                    description: trimmedDescription,
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

private enum PhotoLoadingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Не удалось открыть изображение."
    }
}
