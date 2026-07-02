import Foundation
import SwiftData

enum TagTargetType: String {
    case item
    case container
}

@Model
final class StorageTag: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var parentID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TagAssignment: Identifiable {
    @Attribute(.unique) var id: UUID
    var tagID: UUID
    var targetID: UUID
    var targetTypeRaw: String
    var createdAt: Date

    var targetType: TagTargetType {
        get {
            TagTargetType(rawValue: targetTypeRaw) ?? .item
        }
        set {
            targetTypeRaw = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        tagID: UUID,
        targetID: UUID,
        targetType: TagTargetType,
        createdAt: Date = .now
    ) {
        self.id = id
        self.tagID = tagID
        self.targetID = targetID
        self.targetTypeRaw = targetType.rawValue
        self.createdAt = createdAt
    }
}
