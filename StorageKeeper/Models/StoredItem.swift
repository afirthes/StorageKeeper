import Foundation

struct StoredItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var itemDescription: String
    var containerID: UUID?
    var photoKey: String?
    var tagIds: Set<UUID>
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case itemDescription = "description"
        case containerID = "containerId"
        case photoKey
        case tagIds
        case createdAt
        case updatedAt
    }
}
