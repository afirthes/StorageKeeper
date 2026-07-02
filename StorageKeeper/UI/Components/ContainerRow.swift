import SwiftUI

struct ContainerRow: View {
    @EnvironmentObject private var store: StorageViewModel

    let container: StorageContainer
    let childCount: Int
    let itemCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ItemPhotoView(photoKey: container.primaryDisplayPhotoKey, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("Контейнеры: \(childCount) · Вещи: \(itemCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !tagLine.isEmpty {
                    Text(tagLine)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var containerTags: [StorageTag] {
        TagUtilities.selectedTags(tagIDs: container.tagIds, allTags: store.tags)
    }

    private var tagLine: String {
        TagUtilities.compactTagLine(containerTags, limit: 3)
    }
}

struct ContainerFeedCard: View {
    @EnvironmentObject private var store: StorageViewModel

    let container: StorageContainer
    let childCount: Int
    let itemCount: Int

    var body: some View {
        VStack(spacing: 0) {
            photo
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("Контейнеры: \(childCount) · Вещи: \(itemCount)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                if !visibleContainerTags.isEmpty {
                    TagFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(visibleContainerTags) { tag in
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
        if !container.displayPhotoKeys.isEmpty {
            PhotoGalleryBannerView(
                photoKeys: container.displayPhotoKeys,
                placeholderSystemName: "shippingbox.fill",
                primaryPhotoKey: container.primaryDisplayPhotoKey,
                onPrimaryPhotoChange: { photoKey in
                    Task {
                        try? await store.setPrimaryContainerPhoto(container, photoKey: photoKey)
                    }
                }
            )
        } else {
            ZStack {
                Rectangle()
                    .fill(.secondary.opacity(0.14))

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var containerTags: [StorageTag] {
        TagUtilities.selectedTags(tagIDs: container.tagIds, allTags: store.tags)
    }

    private var visibleContainerTags: [StorageTag] {
        Array(containerTags.prefix(4))
    }
}
