import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject private var store: StorageViewModel

    let searchText: String

    @State private var results = SearchResponse(containers: [], items: [])
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    ProgressView("Поиск")
                }
            } else if results.containers.isEmpty && results.items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Ничего не найдено",
                        systemImage: "magnifyingglass",
                        description: Text("Поиск идет по названиям, описаниям и тегам.")
                    )
                }
            } else {
                if !results.containers.isEmpty {
                    Section("Контейнеры") {
                        ForEach(results.containers) { container in
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

                if !results.items.isEmpty {
                    Section("Вещи") {
                        ForEach(results.items) { item in
                            NavigationLink {
                                ItemDetailView(itemID: item.id)
                            } label: {
                                ItemRow(item: item, footnote: locationTitle(for: item))
                            }
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .task(id: searchText) {
            await search()
        }
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = SearchResponse(containers: [], items: [])
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            results = try await store.search(query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func childCount(for container: StorageContainer) -> Int {
        store.containers.filter { $0.parentID == container.id }.count
    }

    private func itemCount(for container: StorageContainer) -> Int {
        store.items.filter { $0.containerID == container.id }.count
    }

    private func locationTitle(for item: StoredItem) -> String {
        guard let containerID = item.containerID else {
            return "Без контейнера"
        }

        return store.containers.first { $0.id == containerID }?.name ?? "Контейнер не найден"
    }
}
