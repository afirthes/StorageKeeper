import Foundation

struct StorageContainer: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var details: String
    var parentID: UUID?
    var photoKey: String?
    var tagIds: Set<UUID>
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case details
        case parentID = "parentId"
        case photoKey
        case tagIds
        case createdAt
        case updatedAt
    }
}
