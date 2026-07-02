import Foundation

struct StorageContainer: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var details: String
    var parentID: UUID?
    var photoKey: String?
    var photoKeys: [String]
    var primaryPhotoKey: String?
    var tagIds: Set<UUID>
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case details
        case parentID = "parentId"
        case photoKey
        case photoKeys
        case primaryPhotoKey
        case tagIds
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        details = try container.decode(String.self, forKey: .details)
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        photoKey = try container.decodeIfPresent(String.self, forKey: .photoKey)
        photoKeys = try container.decodeIfPresent([String].self, forKey: .photoKeys) ?? (photoKey.map { [$0] } ?? [])
        primaryPhotoKey = try container.decodeIfPresent(String.self, forKey: .primaryPhotoKey) ?? photoKey ?? photoKeys.first
        tagIds = try container.decode(Set<UUID>.self, forKey: .tagIds)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var displayPhotoKeys: [String] {
        let keys = photoKeys.isEmpty ? (photoKey.map { [$0] } ?? []) : photoKeys
        let primaryKey = primaryPhotoKey.flatMap { keys.contains($0) ? $0 : nil }
            ?? photoKey.flatMap { keys.contains($0) ? $0 : nil }

        guard let primaryKey else {
            return keys
        }

        return [primaryKey] + keys.filter { $0 != primaryKey }
    }

    var primaryDisplayPhotoKey: String? {
        displayPhotoKeys.first
    }
}
