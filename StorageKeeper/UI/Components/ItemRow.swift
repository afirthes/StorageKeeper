import SwiftData
import SwiftUI

struct ItemRow: View {
    @Query(sort: \StorageTag.name, order: .forward) private var tags: [StorageTag]
    @Query private var tagAssignments: [TagAssignment]

    let item: StoredItem
    var footnote: String?

    var body: some View {
        HStack(spacing: 12) {
            ItemPhotoView(filename: item.photoFilename, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !trimmedDescription.isEmpty {
                    Text(trimmedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !tagLine.isEmpty {
                    Text(tagLine)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }

                if let footnote {
                    Label(footnote, systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var trimmedDescription: String {
        item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var itemTags: [StorageTag] {
        let tagIDs = TagAssignmentStore.tagIDs(
            for: item.id,
            targetType: .item,
            assignments: tagAssignments
        )

        return TagUtilities.selectedTags(tagIDs: tagIDs, allTags: tags)
    }

    private var tagLine: String {
        TagUtilities.compactTagLine(itemTags, limit: 3)
    }
}

struct ItemFeedCard: View {
    @Query(sort: \StorageTag.name, order: .forward) private var tags: [StorageTag]
    @Query private var tagAssignments: [TagAssignment]

    let item: StoredItem

    var body: some View {
        VStack(spacing: 0) {
            photo
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if !trimmedDescription.isEmpty {
                    Text(trimmedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }

                if !visibleItemTags.isEmpty {
                    TagFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(visibleItemTags) { tag in
                            TagChipView(
                                title: TagUtilities.displayName(tag),
                                isOnDarkBackground: true
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.black.opacity(0.92))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var photo: some View {
        if let image = ItemImageStore.loadImage(named: item.photoFilename) {
            ZStack {
                Rectangle()
                    .fill(.secondary.opacity(0.08))

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(1)
            }
        } else {
            ZStack {
                Rectangle()
                    .fill(.secondary.opacity(0.14))

                Image(systemName: "photo")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trimmedDescription: String {
        item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var itemTags: [StorageTag] {
        let tagIDs = TagAssignmentStore.tagIDs(
            for: item.id,
            targetType: .item,
            assignments: tagAssignments
        )

        return TagUtilities.selectedTags(tagIDs: tagIDs, allTags: tags)
    }

    private var visibleItemTags: [StorageTag] {
        Array(itemTags.prefix(4))
    }
}
