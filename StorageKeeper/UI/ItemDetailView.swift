import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var store: StorageViewModel
    @Environment(\.dismiss) private var dismiss

    let itemID: UUID

    @State private var isEditing = false
    @State private var isConfirmingDeletion = false
    @State private var viewedTagIDs = Set<UUID>()
    @State private var isShowingTagHierarchy = false

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        PhotoGalleryBannerView(
                            photoKeys: item.displayPhotoKeys,
                            placeholderSystemName: "photo",
                            primaryPhotoKey: item.primaryDisplayPhotoKey,
                            onPrimaryPhotoChange: { photoKey in
                                Task {
                                    try? await store.setPrimaryItemPhoto(item, photoKey: photoKey)
                                }
                            }
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.name)
                                .font(.title.bold())
                                .textSelection(.enabled)

                            Label(locationTitle(for: item), systemImage: "shippingbox")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        let itemTags = tags(for: item)
                        if !itemTags.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Теги")
                                    .font(.headline)

                                TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                                    ForEach(itemTags) { tag in
                                        TagChipView(
                                            title: TagUtilities.displayName(tag),
                                            onTap: {
                                                viewedTagIDs = [tag.id]
                                                isShowingTagHierarchy = true
                                            }
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Описание")
                                .font(.headline)

                            if item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Описание пока не добавлено.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle(item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            isEditing = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Редактировать вещь")

                        Button(role: .destructive) {
                            isConfirmingDeletion = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Удалить вещь")
                    }
                }
                .sheet(isPresented: $isEditing) {
                    ItemEditorView(mode: .edit(item))
                }
                .sheet(isPresented: $isShowingTagHierarchy) {
                    NavigationStack {
                        TagHierarchyView(mode: .viewing, selectedTagIDs: .constant(viewedTagIDs))
                    }
                }
                .confirmationDialog("Удалить вещь?", isPresented: $isConfirmingDeletion) {
                    Button("Удалить", role: .destructive) {
                        Task {
                            try? await store.deleteItem(item)
                            dismiss()
                        }
                    }

                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text("Фотография этой вещи тоже будет удалена.")
                }
            } else {
                ContentUnavailableView("Вещь не найдена", systemImage: "tag")
            }
        }
    }

    private var item: StoredItem? {
        store.items.first { $0.id == itemID }
    }

    private func locationTitle(for item: StoredItem) -> String {
        guard let containerID = item.containerID else {
            return "Без контейнера"
        }

        return store.containers.first { $0.id == containerID }?.name ?? "Контейнер не найден"
    }

    private func tags(for item: StoredItem) -> [StorageTag] {
        TagUtilities.selectedTags(tagIDs: item.tagIds, allTags: store.tags)
    }
}
