import SwiftUI

struct ContainerContentView: View {
    @EnvironmentObject private var store: StorageViewModel

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
                            ItemDetailView(itemID: item.id)
                        } label: {
                            ItemFeedCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { try? await store.deleteItem(item) }
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
        .refreshable {
            await store.reload()
        }
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
                Task { try? await store.deleteContainer(container) }
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
        return store.containers.first { $0.id == containerID }
    }

    private var childContainers: [StorageContainer] {
        store.containers
            .filter { $0.parentID == containerID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var visibleItems: [StoredItem] {
        store.items
            .filter { $0.containerID == containerID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var emptyStateDescription: String {
        containerID == nil
            ? "Создайте первый контейнер или добавьте вещь без контейнера."
            : "Добавьте вложенный контейнер или вещь с фотографией."
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
        store.containers.filter { $0.parentID == container.id }.count
    }

    private func itemCount(for container: StorageContainer) -> Int {
        store.items.filter { $0.containerID == container.id }.count
    }

    private func tags(for container: StorageContainer) -> [StorageTag] {
        TagUtilities.selectedTags(tagIDs: container.tagIds, allTags: store.tags)
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
