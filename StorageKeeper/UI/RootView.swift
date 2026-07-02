import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: StorageViewModel
    @State private var searchText = ""
    @State private var selectedTab: AppTab = .storage

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Group {
                    if !store.isAuthenticated {
                        ConnectionRequiredView()
                    } else if trimmedSearchText.isEmpty {
                        ContainerContentView(containerID: nil)
                    } else {
                        SearchResultsView(searchText: trimmedSearchText)
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
            .tag(AppTab.storage)

            NavigationStack {
                if store.isAuthenticated {
                    TagHierarchyView()
                } else {
                    ConnectionRequiredView()
                        .navigationTitle("Теги")
                }
            }
            .tabItem {
                Label("Теги", systemImage: "tag")
            }
            .tag(AppTab.tags)

            NavigationStack {
                SettingsView {
                    selectedTab = .storage
                }
            }
            .tabItem {
                Label("Настройки", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .overlay(alignment: .top) {
            if let errorMessage = store.errorMessage, store.isAuthenticated {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.red.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding()
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum AppTab: Hashable {
    case storage
    case tags
    case settings
}

private struct ConnectionRequiredView: View {
    var body: some View {
        ContentUnavailableView(
            "Подключите сервер",
            systemImage: "network",
            description: Text("Откройте настройки, укажите адрес сервера, логин и пароль.")
        )
    }
}
