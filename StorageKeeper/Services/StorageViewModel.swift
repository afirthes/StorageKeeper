import Foundation
import SwiftUI

struct PhotoDraftPayload: Identifiable, Equatable {
    let id: UUID
    var photoKey: String?
    var data: Data?

    init(id: UUID = UUID(), photoKey: String? = nil, data: Data? = nil) {
        self.id = id
        self.photoKey = photoKey
        self.data = data
    }
}

@MainActor
final class StorageViewModel: ObservableObject {
    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }
    @Published var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }
    @Published var password: String {
        didSet { KeychainStore.set(password.isEmpty ? nil : password, for: Keys.password) }
    }
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published private(set) var containers: [StorageContainer] = []
    @Published private(set) var items: [StoredItem] = []
    @Published private(set) var tags: [StorageTag] = []
    @Published var errorMessage: String?
    @Published var authChallenge: AuthChallengeResponse?

    private let defaults = UserDefaults.standard
    private let api = APIClient()
    private var accessToken: String? {
        didSet {
            api.accessToken = accessToken
            KeychainStore.set(accessToken, for: Keys.accessToken)
        }
    }
    private var refreshToken: String? {
        didSet { KeychainStore.set(refreshToken, for: Keys.refreshToken) }
    }

    init() {
        serverURL = defaults.string(forKey: Keys.serverURL) ?? ""
        username = defaults.string(forKey: Keys.username) ?? ""
        password = KeychainStore.string(for: Keys.password) ?? ""
        accessToken = KeychainStore.string(for: Keys.accessToken)
        refreshToken = KeychainStore.string(for: Keys.refreshToken)
        api.serverURL = serverURL
        api.accessToken = accessToken

        Task {
            await bootstrap()
        }
    }

    var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var containersByID: [UUID: StorageContainer] {
        Dictionary(uniqueKeysWithValues: containers.map { ($0.id, $0) })
    }

    func bootstrap() async {
        guard isConfigured else {
            return
        }

        api.serverURL = serverURL
        if let refreshToken, !refreshToken.isEmpty {
            do {
                try await refreshAuth(refreshToken: refreshToken)
                try await refreshData()
            } catch {
                isAuthenticated = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveConnectionSettings() {
        api.serverURL = serverURL
        defaults.set(serverURL, forKey: Keys.serverURL)
        defaults.set(username, forKey: Keys.username)
        KeychainStore.set(password.isEmpty ? nil : password, for: Keys.password)
    }

    func checkServer() async {
        await run {
            self.api.serverURL = self.serverURL
            let status: AuthStatusResponse = try await self.api.get("/auth/status")
            self.authChallenge = status.challenge
            if !status.configured {
                throw APIError.message("На сервере не настроены логин и пароль.")
            }
        }
    }

    func login(captchaAnswer: String = "") async {
        await run {
            self.saveConnectionSettings()
            let response: AuthResponse = try await self.api.post("/auth/login", body: AuthRequest(
                username: self.username,
                password: self.password,
                captchaId: self.authChallenge?.captchaId,
                captchaAnswer: captchaAnswer.isEmpty ? nil : captchaAnswer
            ))
            self.applyAuth(response)
            try await self.refreshData()
        } onError: {
            await self.loadChallenge()
        }
    }

    func logout() async {
        if let refreshToken {
            let _: EmptyResponse? = try? await api.post("/auth/logout", body: RefreshRequest(refreshToken: refreshToken))
        }
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        containers = []
        items = []
        tags = []
    }

    func refreshData() async throws {
        try await authenticated {
            self.containers = try await self.api.get("/containers")
            self.items = try await self.api.get("/items")
            self.tags = try await self.api.get("/tags")
        }
    }

    func reload() async {
        await run {
            try await self.refreshData()
        }
    }

    func search(_ query: String) async throws -> SearchResponse {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await authenticated {
            try await self.api.get("/search?q=\(escaped)")
        }
    }

    func photoData(for key: String) async throws -> Data {
        try await authenticated {
            try await self.api.photoData(for: key)
        }
    }

    func createContainer(name: String, details: String, parentID: UUID?, photos: [PhotoDraftPayload], primaryPhotoID: UUID?, tagIDs: Set<UUID>) async throws {
        try await authenticated {
            let photoPayload = try await self.uploadPhotos(photos, primaryPhotoID: primaryPhotoID, folder: "containers")
            let _: StorageContainer = try await self.api.post("/containers", body: ContainerSaveRequest(
                name: name,
                details: details,
                parentId: parentID,
                photoKey: photoPayload.primaryPhotoKey,
                photoKeys: photoPayload.photoKeys,
                primaryPhotoKey: photoPayload.primaryPhotoKey,
                tagIds: tagIDs
            ))
            try await self.refreshData()
        }
    }

    func updateContainer(_ container: StorageContainer, name: String, details: String, photos: [PhotoDraftPayload], primaryPhotoID: UUID?, tagIDs: Set<UUID>) async throws {
        try await authenticated {
            let photoPayload = try await self.uploadPhotos(photos, primaryPhotoID: primaryPhotoID, folder: "containers")

            let _: StorageContainer = try await self.api.patch("/containers/\(container.id.uuidString)", body: ContainerPatchRequest(
                name: name,
                details: details,
                parentId: container.parentID,
                photoKey: photoPayload.primaryPhotoKey ?? "",
                photoKeys: photoPayload.photoKeys,
                primaryPhotoKey: photoPayload.primaryPhotoKey
            ))
            let _: StorageContainer = try await self.api.put("/containers/\(container.id.uuidString)/tags", body: TagAssignmentRequest(tagIds: tagIDs))
            try await self.refreshData()
        }
    }

    func setPrimaryContainerPhoto(_ container: StorageContainer, photoKey: String) async throws {
        guard container.primaryDisplayPhotoKey != photoKey else {
            return
        }

        try await authenticated {
            let photoKeys = Self.photoKeys(container.displayPhotoKeys, movingFirst: photoKey)
            let updated: StorageContainer = try await self.api.patch("/containers/\(container.id.uuidString)", body: PhotoPrimaryPatchRequest(
                photoKey: photoKey,
                photoKeys: photoKeys,
                primaryPhotoKey: photoKey
            ))
            self.containers = self.containers.map { $0.id == updated.id ? updated : $0 }
        }
    }

    func deleteContainer(_ container: StorageContainer) async throws {
        try await authenticated {
            try await self.api.delete("/containers/\(container.id.uuidString)")
            try await self.refreshData()
        }
    }

    func createItem(name: String, description: String, containerID: UUID?, photos: [PhotoDraftPayload], primaryPhotoID: UUID?, tagIDs: Set<UUID>) async throws {
        try await authenticated {
            let photoPayload = try await self.uploadPhotos(photos, primaryPhotoID: primaryPhotoID, folder: "items")
            let _: StoredItem = try await self.api.post("/items", body: ItemSaveRequest(
                name: name,
                description: description,
                containerId: containerID,
                photoKey: photoPayload.primaryPhotoKey,
                photoKeys: photoPayload.photoKeys,
                primaryPhotoKey: photoPayload.primaryPhotoKey,
                tagIds: tagIDs
            ))
            try await self.refreshData()
        }
    }

    func updateItem(_ item: StoredItem, name: String, description: String, photos: [PhotoDraftPayload], primaryPhotoID: UUID?, tagIDs: Set<UUID>) async throws {
        try await authenticated {
            let photoPayload = try await self.uploadPhotos(photos, primaryPhotoID: primaryPhotoID, folder: "items")

            let _: StoredItem = try await self.api.patch("/items/\(item.id.uuidString)", body: ItemPatchRequest(
                name: name,
                description: description,
                containerId: item.containerID,
                photoKey: photoPayload.primaryPhotoKey ?? "",
                photoKeys: photoPayload.photoKeys,
                primaryPhotoKey: photoPayload.primaryPhotoKey
            ))
            let _: StoredItem = try await self.api.put("/items/\(item.id.uuidString)/tags", body: TagAssignmentRequest(tagIds: tagIDs))
            try await self.refreshData()
        }
    }

    func setPrimaryItemPhoto(_ item: StoredItem, photoKey: String) async throws {
        guard item.primaryDisplayPhotoKey != photoKey else {
            return
        }

        try await authenticated {
            let photoKeys = Self.photoKeys(item.displayPhotoKeys, movingFirst: photoKey)
            let updated: StoredItem = try await self.api.patch("/items/\(item.id.uuidString)", body: PhotoPrimaryPatchRequest(
                photoKey: photoKey,
                photoKeys: photoKeys,
                primaryPhotoKey: photoKey
            ))
            self.items = self.items.map { $0.id == updated.id ? updated : $0 }
        }
    }

    func deleteItem(_ item: StoredItem) async throws {
        try await authenticated {
            try await self.api.delete("/items/\(item.id.uuidString)")
            try await self.refreshData()
        }
    }

    func createTag(name: String, parentID: UUID?) async throws -> StorageTag {
        try await authenticated {
            let tag: StorageTag = try await self.api.post("/tags", body: TagSaveRequest(name: name, parentId: parentID))
            try await self.refreshData()
            return tag
        }
    }

    func updateTag(_ tag: StorageTag, name: String) async throws {
        try await authenticated {
            let _: StorageTag = try await self.api.patch("/tags/\(tag.id.uuidString)", body: TagSaveRequest(name: name, parentId: tag.parentID))
            try await self.refreshData()
        }
    }

    func deleteTag(_ tag: StorageTag) async throws {
        try await authenticated {
            try await self.api.delete("/tags/\(tag.id.uuidString)")
            try await self.refreshData()
        }
    }

    private func uploadPhotos(_ photos: [PhotoDraftPayload], primaryPhotoID: UUID?, folder: String) async throws -> (photoKeys: [String], primaryPhotoKey: String?) {
        var uploaded: [(id: UUID, key: String)] = []

        for photo in photos {
            if let data = photo.data {
                uploaded.append((photo.id, try await api.uploadPhoto(data, folder: folder).key))
            } else if let photoKey = photo.photoKey, !photoKey.isEmpty {
                uploaded.append((photo.id, photoKey))
            }
        }

        let photoKeys = uploaded.map(\.key)
        let primaryPhotoKey = uploaded.first { $0.id == primaryPhotoID }?.key ?? photoKeys.first
        return (photoKeys, primaryPhotoKey)
    }

    private static func photoKeys(_ keys: [String], movingFirst primaryKey: String) -> [String] {
        [primaryKey] + keys.filter { $0 != primaryKey }
    }

    private func authenticated<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch APIError.unauthorized {
            guard let refreshToken else {
                isAuthenticated = false
                throw APIError.unauthorized
            }
            try await refreshAuth(refreshToken: refreshToken)
            return try await operation()
        }
    }

    private func refreshAuth(refreshToken: String) async throws {
        let response: AuthResponse = try await api.post("/auth/refresh", body: RefreshRequest(refreshToken: refreshToken))
        applyAuth(response)
    }

    private func loadChallenge() async {
        do {
            let challenge: AuthChallengeResponse = try await api.get("/auth/challenge")
            authChallenge = challenge
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyAuth(_ response: AuthResponse) {
        username = response.username
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        isAuthenticated = true
        authChallenge = nil
        errorMessage = nil
    }

    private func run(_ operation: () async throws -> Void, onError: (() async -> Void)? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            await onError?()
        }
    }
}

private enum Keys {
    static let serverURL = "storagekeeper.serverURL"
    static let username = "storagekeeper.username"
    static let password = "storagekeeper.password"
    static let accessToken = "storagekeeper.accessToken"
    static let refreshToken = "storagekeeper.refreshToken"
}

private struct AuthRequest: Codable {
    var username: String
    var password: String
    var captchaId: String?
    var captchaAnswer: String?
}

private struct RefreshRequest: Codable {
    var refreshToken: String
}

private struct ContainerSaveRequest: Codable {
    var name: String
    var details: String
    var parentId: UUID?
    var photoKey: String?
    var photoKeys: [String]
    var primaryPhotoKey: String?
    var tagIds: Set<UUID>
}

private struct ContainerPatchRequest: Codable {
    var name: String
    var details: String
    var parentId: UUID?
    var photoKey: String?
    var photoKeys: [String]
    var primaryPhotoKey: String?
}

private struct ItemSaveRequest: Codable {
    var name: String
    var description: String
    var containerId: UUID?
    var photoKey: String?
    var photoKeys: [String]
    var primaryPhotoKey: String?
    var tagIds: Set<UUID>
}

private struct ItemPatchRequest: Codable {
    var name: String
    var description: String
    var containerId: UUID?
    var photoKey: String?
    var photoKeys: [String]
    var primaryPhotoKey: String?
}

private struct PhotoPrimaryPatchRequest: Codable {
    var photoKey: String
    var photoKeys: [String]
    var primaryPhotoKey: String
}

private struct TagSaveRequest: Codable {
    var name: String
    var parentId: UUID?
}

private struct TagAssignmentRequest: Codable {
    var tagIds: Set<UUID>
}
