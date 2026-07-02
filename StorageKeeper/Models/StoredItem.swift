import Foundation
import SwiftData

@Model
final class StoredItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var itemDescription: String
    var photoFilename: String?
    var containerID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        itemDescription: String = "",
        photoFilename: String? = nil,
        containerID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.itemDescription = itemDescription
        self.photoFilename = photoFilename
        self.containerID = containerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
