import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum ItemEditorMode {
    case create(containerID: UUID?)
    case edit(StoredItem)
}

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \StorageTag.name, order: .forward) private var tags: [StorageTag]
    @Query private var tagAssignments: [TagAssignment]

    private let mode: ItemEditorMode

    @State private var name: String
    @State private var itemDescription: String
    @State private var photoFilename: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var cropRequest: PhotoCropRequest?
    @State private var isShowingCamera = false
    @State private var selectedTagIDs = Set<UUID>()
    @State private var didLoadTags = false
    @State private var isShowingTagPicker = false
    @State private var errorMessage: String?

    init(mode: ItemEditorMode) {
        self.mode = mode

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _itemDescription = State(initialValue: "")
            _photoFilename = State(initialValue: nil)
        case .edit(let item):
            _name = State(initialValue: item.name)
            _itemDescription = State(initialValue: item.itemDescription)
            _photoFilename = State(initialValue: item.photoFilename)
        }
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

                    if photoFilename != nil || selectedPhotoData != nil {
                        Button("Удалить фото", role: .destructive) {
                            selectedPhotoData = nil
                            selectedPhotoItem = nil
                            photoFilename = nil
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
            .onAppear {
                loadSelectedTagsIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
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

    private var photoPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.12))

            if let selectedPhotoData,
               let image = UIImage(data: selectedPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let image = ItemImageStore.loadImage(named: photoFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .medium))
                    Text("Фото вещи")
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
        let selectedTags = TagUtilities.selectedTags(tagIDs: selectedTagIDs, allTags: tags)

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

    private func loadSelectedTagsIfNeeded() {
        guard !didLoadTags else {
            return
        }

        didLoadTags = true

        guard case .edit(let item) = mode else {
            return
        }

        selectedTagIDs = TagAssignmentStore.tagIDs(
            for: item.id,
            targetType: .item,
            assignments: tagAssignments
        )
    }

    private func save() {
        do {
            var finalPhotoFilename = photoFilename

            if let selectedPhotoData {
                finalPhotoFilename = try ItemImageStore.savePhotoData(
                    selectedPhotoData,
                    replacing: photoFilename
                )
            }

            switch mode {
            case .create(let containerID):
                let newItem = StoredItem(
                    name: trimmedName,
                    itemDescription: trimmedDescription,
                    photoFilename: finalPhotoFilename,
                    containerID: containerID
                )
                modelContext.insert(newItem)
                TagAssignmentStore.sync(
                    targetID: newItem.id,
                    targetType: .item,
                    selectedTagIDs: selectedTagIDs,
                    assignments: tagAssignments,
                    modelContext: modelContext
                )

            case .edit(let item):
                let oldPhotoFilename = item.photoFilename

                item.name = trimmedName
                item.itemDescription = trimmedDescription
                item.photoFilename = finalPhotoFilename
                item.updatedAt = .now

                if oldPhotoFilename != finalPhotoFilename {
                    ItemImageStore.deletePhoto(named: oldPhotoFilename)
                }

                TagAssignmentStore.sync(
                    targetID: item.id,
                    targetType: .item,
                    selectedTagIDs: selectedTagIDs,
                    assignments: tagAssignments,
                    modelContext: modelContext
                )
            }

            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum PhotoLoadingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Не удалось открыть изображение."
    }
}
