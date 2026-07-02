import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \StorageContainer.name, order: .forward) private var containers: [StorageContainer]
    @Query(sort: \StoredItem.name, order: .forward) private var items: [StoredItem]
    @Query(sort: \StorageTag.name, order: .forward) private var tags: [StorageTag]
    @Query private var tagAssignments: [TagAssignment]

    @State private var searchText = ""

    var body: some View {
        TabView {
            NavigationStack {
                Group {
                    if trimmedSearchText.isEmpty {
                        ContainerContentView(containerID: nil)
                    } else {
                        SearchResultsView(
                            searchText: trimmedSearchText,
                            containers: containers,
                            items: items,
                            tags: tags,
                            tagAssignments: tagAssignments
                        )
                    }
                }
                .navigationTitle(trimmedSearchText.isEmpty ? "Хранилище" : "Поиск")
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Название или тег"
                )
            }
            .tabItem {
                Label("Хранилище", systemImage: "archivebox")
            }

            NavigationStack {
                TagHierarchyView()
            }
            .tabItem {
                Label("Теги", systemImage: "tag")
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
