import Foundation

enum TagTargetType: String {
    case item
    case container
}

struct StorageTag: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var parentID: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID = "parentId"
        case createdAt
        case updatedAt
    }
}

struct SearchResponse: Codable {
    var containers: [StorageContainer]
    var items: [StoredItem]
}

struct PhotoResponse: Codable {
    var key: String
    var url: String
    var contentType: String
    var size: Int
}
