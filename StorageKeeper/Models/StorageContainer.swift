import Foundation
import SwiftData

@Model
final class StorageContainer: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var details: String
    var photoFilename: String?
    var parentID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        details: String = "",
        photoFilename: String? = nil,
        parentID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.photoFilename = photoFilename
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
