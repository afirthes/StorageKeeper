import SwiftUI

struct TagChipView: View {
    let title: String
    var isOnDarkBackground = false
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            if let onTap {
                Button(action: onTap) {
                    titleView
                }
                .buttonStyle(.plain)
            } else {
                titleView
            }

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(removeColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить тег")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var titleView: some View {
        Text(title)
            .lineLimit(1)
    }

    private var textColor: Color {
        isOnDarkBackground ? .white : .primary
    }

    private var removeColor: Color {
        isOnDarkBackground ? .white.opacity(0.72) : .secondary
    }

    private var backgroundColor: Color {
        isOnDarkBackground ? .white.opacity(0.10) : .secondary.opacity(0.10)
    }

    private var borderColor: Color {
        isOnDarkBackground ? .white.opacity(0.38) : .secondary.opacity(0.28)
    }
}

struct TagFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = arrangedRows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let contentWidth = rows.map(\.width).max() ?? 0
        let contentHeight = rows.last.map { $0.yOffset + $0.height } ?? 0
        let proposedWidth = proposal.width ?? contentWidth

        return CGSize(width: proposedWidth, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrangedRows(for: subviews, maxWidth: bounds.width)

        for row in rows {
            var x = bounds.minX

            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.yOffset),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
        }
    }

    private func arrangedRows(for subviews: Subviews, maxWidth: CGFloat) -> [TagFlowRow] {
        var rows: [TagFlowRow] = []
        var currentItems: [TagFlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var yOffset: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let spacing = currentItems.isEmpty ? 0 : horizontalSpacing
            let wouldOverflow = currentWidth + spacing + size.width > maxWidth

            if wouldOverflow && !currentItems.isEmpty {
                rows.append(
                    TagFlowRow(
                        items: currentItems,
                        width: currentWidth,
                        height: currentHeight,
                        yOffset: yOffset
                    )
                )
                yOffset += currentHeight + verticalSpacing
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            let itemSpacing = currentItems.isEmpty ? 0 : horizontalSpacing
            currentItems.append(TagFlowItem(index: index, size: size))
            currentWidth += itemSpacing + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(
                TagFlowRow(
                    items: currentItems,
                    width: currentWidth,
                    height: currentHeight,
                    yOffset: yOffset
                )
            )
        }

        return rows
    }
}

private struct TagFlowItem {
    let index: Int
    let size: CGSize
}

private struct TagFlowRow {
    let items: [TagFlowItem]
    let width: CGFloat
    let height: CGFloat
    let yOffset: CGFloat
}
