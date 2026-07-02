import SwiftUI

struct SearchResultsView: View {
    let searchText: String
    let containers: [StorageContainer]
    let items: [StoredItem]
    let tags: [StorageTag]
    let tagAssignments: [TagAssignment]

    var body: some View {
        List {
            if matchingContainers.isEmpty && matchingItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Ничего не найдено",
                        systemImage: "magnifyingglass",
                        description: Text("Поиск идет по названиям и тегам.")
                    )
                }
            } else {
                if !matchingContainers.isEmpty {
                    Section("Контейнеры") {
                        ForEach(matchingContainers) { container in
                            NavigationLink {
                                ContainerContentView(containerID: container.id)
                            } label: {
                                ContainerRow(
                                    container: container,
                                    childCount: childCount(for: container),
                                    itemCount: itemCount(for: container)
                                )
                            }
                        }
                    }
                }

                if !matchingItems.isEmpty {
                    Section("Вещи") {
                        ForEach(matchingItems) { item in
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                ItemRow(item: item, footnote: locationTitle(for: item))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var matchingContainers: [StorageContainer] {
        containers
            .filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                hasMatchingTag(targetID: $0.id, targetType: .container)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var matchingItems: [StoredItem] {
        items
            .filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                hasMatchingTag(targetID: $0.id, targetType: .item)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var matchingTagIDs: Set<UUID> {
        let query = TagUtilities.normalizedTagName(searchText)

        guard !query.isEmpty else {
            return []
        }

        let directTagIDs = Set(
            tags
                .filter {
                    $0.name.localizedCaseInsensitiveContains(query) ||
                    TagUtilities.path(for: $0, in: tags).localizedCaseInsensitiveContains(query)
                }
                .map(\.id)
        )

        return TagUtilities.descendantIDs(of: directTagIDs, in: tags)
    }

    private func hasMatchingTag(targetID: UUID, targetType: TagTargetType) -> Bool {
        guard !matchingTagIDs.isEmpty else {
            return false
        }

        return tagAssignments.contains {
            $0.targetID == targetID &&
            $0.targetTypeRaw == targetType.rawValue &&
            matchingTagIDs.contains($0.tagID)
        }
    }

    private func childCount(for container: StorageContainer) -> Int {
        containers.filter { $0.parentID == container.id }.count
    }

    private func itemCount(for container: StorageContainer) -> Int {
        items.filter { $0.containerID == container.id }.count
    }

    private func locationTitle(for item: StoredItem) -> String {
        guard let containerID = item.containerID else {
            return "Без контейнера"
        }

        return containers.first { $0.id == containerID }?.name ?? "Контейнер не найден"
    }
}
