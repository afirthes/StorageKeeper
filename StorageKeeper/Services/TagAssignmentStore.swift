import Foundation
import SwiftData

enum TagUtilities {
    static func normalizedTagName(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        while value.hasPrefix("#") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    static func displayName(_ tag: StorageTag) -> String {
        tag.name
    }

    static func path(for tag: StorageTag, in tags: [StorageTag]) -> String {
        let index = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        var path: [String] = [displayName(tag)]
        var currentParentID = tag.parentID
        var visitedIDs = Set<UUID>([tag.id])

        while let parentID = currentParentID,
              let parent = index[parentID],
              !visitedIDs.contains(parent.id) {
            path.insert(displayName(parent), at: 0)
            visitedIDs.insert(parent.id)
            currentParentID = parent.parentID
        }

        return path.joined(separator: " / ")
    }

    static func sortedTags(_ tags: [StorageTag], in allTags: [StorageTag]) -> [StorageTag] {
        tags.sorted {
            path(for: $0, in: allTags).localizedCaseInsensitiveCompare(path(for: $1, in: allTags)) == .orderedAscending
        }
    }

    static func descendantIDs(of rootIDs: Set<UUID>, in tags: [StorageTag]) -> Set<UUID> {
        var result = rootIDs
        var didAddTag = true

        while didAddTag {
            didAddTag = false

            for tag in tags {
                guard let parentID = tag.parentID else {
                    continue
                }

                if result.contains(parentID) && !result.contains(tag.id) {
                    result.insert(tag.id)
                    didAddTag = true
                }
            }
        }

        return result
    }

    static func selectedTags(tagIDs: Set<UUID>, allTags: [StorageTag]) -> [StorageTag] {
        sortedTags(allTags.filter { tagIDs.contains($0.id) }, in: allTags)
    }

    static func compactTagLine(_ tags: [StorageTag], limit: Int = 4) -> String {
        let visibleTags = tags.prefix(limit).map(displayName)
        let hiddenCount = tags.count - visibleTags.count

        if hiddenCount > 0 {
            return (visibleTags + ["+\(hiddenCount)"]).joined(separator: " ")
        }

        return visibleTags.joined(separator: " ")
    }
}

enum TagAssignmentStore {
    static func tagIDs(
        for targetID: UUID,
        targetType: TagTargetType,
        assignments: [TagAssignment]
    ) -> Set<UUID> {
        Set(
            assignments
                .filter { $0.targetID == targetID && $0.targetTypeRaw == targetType.rawValue }
                .map(\.tagID)
        )
    }

    static func sync(
        targetID: UUID,
        targetType: TagTargetType,
        selectedTagIDs: Set<UUID>,
        assignments: [TagAssignment],
        modelContext: ModelContext
    ) {
        let existingAssignments = assignments.filter {
            $0.targetID == targetID && $0.targetTypeRaw == targetType.rawValue
        }
        let existingTagIDs = Set(existingAssignments.map(\.tagID))

        for assignment in existingAssignments where !selectedTagIDs.contains(assignment.tagID) {
            modelContext.delete(assignment)
        }

        for tagID in selectedTagIDs.subtracting(existingTagIDs) {
            modelContext.insert(
                TagAssignment(
                    tagID: tagID,
                    targetID: targetID,
                    targetType: targetType
                )
            )
        }
    }

    static func deleteAssignments(
        for targetID: UUID,
        targetType: TagTargetType,
        assignments: [TagAssignment],
        modelContext: ModelContext
    ) {
        for assignment in assignments where assignment.targetID == targetID && assignment.targetTypeRaw == targetType.rawValue {
            modelContext.delete(assignment)
        }
    }
}
