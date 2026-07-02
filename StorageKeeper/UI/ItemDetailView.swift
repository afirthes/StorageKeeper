import SwiftData
import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \StorageContainer.name, order: .forward) private var containers: [StorageContainer]
    @Query(sort: \StorageTag.name, order: .forward) private var tags: [StorageTag]
    @Query private var tagAssignments: [TagAssignment]

    let item: StoredItem

    @State private var isEditing = false
    @State private var isConfirmingDeletion = false
    @State private var viewedTagIDs = Set<UUID>()
    @State private var isShowingTagHierarchy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ItemPhotoBannerView(filename: item.photoFilename)

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name)
                        .font(.title.bold())
                        .textSelection(.enabled)

                    Label(locationTitle, systemImage: "shippingbox")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

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

                    if trimmedDescription.isEmpty {
                        Text("Описание пока не добавлено.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(trimmedDescription)
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
                deleteItem()
            }

            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Фотография этой вещи тоже будет удалена.")
        }
    }

    private var trimmedDescription: String {
        item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var locationTitle: String {
        guard let containerID = item.containerID else {
            return "Без контейнера"
        }

        return containers.first { $0.id == containerID }?.name ?? "Контейнер не найден"
    }

    private var itemTags: [StorageTag] {
        let tagIDs = TagAssignmentStore.tagIDs(
            for: item.id,
            targetType: .item,
            assignments: tagAssignments
        )

        return TagUtilities.selectedTags(tagIDs: tagIDs, allTags: tags)
    }

    private func deleteItem() {
        ItemImageStore.deletePhoto(named: item.photoFilename)
        TagAssignmentStore.deleteAssignments(
            for: item.id,
            targetType: .item,
            assignments: tagAssignments,
            modelContext: modelContext
        )
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}
