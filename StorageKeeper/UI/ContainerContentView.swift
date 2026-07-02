import SwiftData
import SwiftUI

struct ContainerContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \StorageContainer.name, order: .forward) private var containers: [StorageContainer]
    @Query(sort: \StoredItem.name, order: .forward) private var items: [StoredItem]
    @Query(sort: \StorageTag.name, order: .forward) private var tags: [StorageTag]
    @Query private var tagAssignments: [TagAssignment]

    let containerID: UUID?

    @State private var activeSheet: ActiveSheet?
    @State private var containerPendingDeletion: StorageContainer?
    @State private var viewedTagIDs = Set<UUID>()
    @State private var isShowingTagHierarchy = false

    var body: some View {
        List {
            if let currentContainer, !tags(for: currentContainer).isEmpty {
                Section("Теги") {
                    TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(tags(for: currentContainer)) { tag in
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
                    .padding(.vertical, 4)
                }
            }

            if childContainers.isEmpty && visibleItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Пока пусто",
                        systemImage: "archivebox",
                        description: Text(emptyStateDescription)
                    )
                }
            }

            if !childContainers.isEmpty {
                Section("Контейнеры") {
                    ForEach(childContainers) { container in
                        NavigationLink {
                            ContainerContentView(containerID: container.id)
                        } label: {
                            ContainerFeedCard(
                                container: container,
                                childCount: childCount(for: container),
                                itemCount: itemCount(for: container)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                containerPendingDeletion = container
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }

                            Button {
                                activeSheet = .editContainer(container)
                            } label: {
                                Label("Править", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }

            if !visibleItems.isEmpty {
                Section("Вещи") {
                    ForEach(visibleItems) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            ItemFeedCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }

                            Button {
                                activeSheet = .editItem(item)
                            } label: {
                                Label("Править", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentContainer?.name ?? "Хранилище")
        .navigationBarTitleDisplayMode(containerID == nil ? .large : .inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let currentContainer {
                    Button {
                        activeSheet = .editContainer(currentContainer)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Редактировать контейнер")
                }

                Menu {
                    Button {
                        activeSheet = .newContainer
                    } label: {
                        Label("Новый контейнер", systemImage: "shippingbox")
                    }

                    Button {
                        activeSheet = .newItem
                    } label: {
                        Label("Новая вещь", systemImage: "tag")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Добавить")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newContainer:
                ContainerEditorView(parentID: containerID)
            case .newItem:
                ItemEditorView(mode: .create(containerID: containerID))
            case .editContainer(let container):
                ContainerEditorView(container: container, parentID: container.parentID)
            case .editItem(let item):
                ItemEditorView(mode: .edit(item))
            }
        }
        .sheet(isPresented: $isShowingTagHierarchy) {
            NavigationStack {
                TagHierarchyView(mode: .viewing, selectedTagIDs: .constant(viewedTagIDs))
            }
        }
        .confirmationDialog(
            "Удалить контейнер?",
            isPresented: isConfirmingContainerDeletion,
            presenting: containerPendingDeletion
        ) { container in
            Button("Удалить со всем содержимым", role: .destructive) {
                deleteContainerTree(container)
                containerPendingDeletion = nil
            }

            Button("Отмена", role: .cancel) {
                containerPendingDeletion = nil
            }
        } message: { _ in
            Text("Будут удалены вложенные контейнеры, вещи и их фотографии.")
        }
    }

    private var currentContainer: StorageContainer? {
        guard let containerID else {
            return nil
        }

        return containers.first { $0.id == containerID }
    }

    private var childContainers: [StorageContainer] {
        containers
            .filter { $0.parentID == containerID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var visibleItems: [StoredItem] {
        items
            .filter { $0.containerID == containerID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var emptyStateDescription: String {
        if containerID == nil {
            return "Создайте первый контейнер или добавьте вещь без контейнера."
        }

        return "Добавьте вложенный контейнер или вещь с фотографией."
    }

    private var isConfirmingContainerDeletion: Binding<Bool> {
        Binding(
            get: { containerPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    containerPendingDeletion = nil
                }
            }
        )
    }

    private func childCount(for container: StorageContainer) -> Int {
        containers.filter { $0.parentID == container.id }.count
    }

    private func itemCount(for container: StorageContainer) -> Int {
        items.filter { $0.containerID == container.id }.count
    }

    private func tags(for container: StorageContainer) -> [StorageTag] {
        let tagIDs = TagAssignmentStore.tagIDs(
            for: container.id,
            targetType: .container,
            assignments: tagAssignments
        )

        return TagUtilities.selectedTags(tagIDs: tagIDs, allTags: tags)
    }

    private func deleteItem(_ item: StoredItem) {
        ItemImageStore.deletePhoto(named: item.photoFilename)
        TagAssignmentStore.deleteAssignments(
            for: item.id,
            targetType: .item,
            assignments: tagAssignments,
            modelContext: modelContext
        )
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func deleteContainerTree(_ container: StorageContainer) {
        var idsToDelete = Set<UUID>([container.id])
        var foundNewChild = true

        while foundNewChild {
            foundNewChild = false

            for candidate in containers {
                guard let parentID = candidate.parentID else {
                    continue
                }

                if idsToDelete.contains(parentID) && !idsToDelete.contains(candidate.id) {
                    idsToDelete.insert(candidate.id)
                    foundNewChild = true
                }
            }
        }

        for item in items where item.containerID.map(idsToDelete.contains) == true {
            ItemImageStore.deletePhoto(named: item.photoFilename)
            TagAssignmentStore.deleteAssignments(
                for: item.id,
                targetType: .item,
                assignments: tagAssignments,
                modelContext: modelContext
            )
            modelContext.delete(item)
        }

        for container in containers where idsToDelete.contains(container.id) {
            ItemImageStore.deletePhoto(named: container.photoFilename)
            TagAssignmentStore.deleteAssignments(
                for: container.id,
                targetType: .container,
                assignments: tagAssignments,
                modelContext: modelContext
            )
            modelContext.delete(container)
        }

        try? modelContext.save()
    }
}

private enum ActiveSheet: Identifiable {
    case newContainer
    case newItem
    case editContainer(StorageContainer)
    case editItem(StoredItem)

    var id: String {
        switch self {
        case .newContainer:
            return "new-container"
        case .newItem:
            return "new-item"
        case .editContainer(let container):
            return "edit-container-\(container.id.uuidString)"
        case .editItem(let item):
            return "edit-item-\(item.id.uuidString)"
        }
    }
}
