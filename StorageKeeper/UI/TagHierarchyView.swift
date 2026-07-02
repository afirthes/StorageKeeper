import SwiftUI

enum TagHierarchyMode {
    case manage
    case selection
    case viewing
}

struct TagHierarchyView: View {
    @EnvironmentObject private var store: StorageViewModel
    @Environment(\.dismiss) private var dismiss

    let mode: TagHierarchyMode
    @Binding private var selectedTagIDs: Set<UUID>

    @State private var expandedTagIDs = Set<UUID>()
    @State private var editRequest: TagEditRequest?
    @State private var pendingDeletionTagID: UUID?
    @State private var errorMessage: String?

    init(mode: TagHierarchyMode = .manage, selectedTagIDs: Binding<Set<UUID>> = .constant([])) {
        self.mode = mode
        _selectedTagIDs = selectedTagIDs
    }

    var body: some View {
        List {
            if store.tags.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Тегов пока нет",
                        systemImage: "tag",
                        description: Text("Создайте первый тег.")
                    )
                }
            } else {
                Section {
                    ForEach(visibleNodes) { node in
                        TagTreeRow(
                            node: node,
                            mode: mode,
                            isSelected: selectedTagIDs.contains(node.tag.id),
                            onToggleExpansion: {
                                toggleExpansion(for: node.tag)
                            },
                            onToggleSelection: {
                                toggleSelection(for: node.tag)
                            },
                            onAddChild: {
                                editRequest = .create(parentID: node.tag.id)
                            },
                            onRename: {
                                editRequest = .rename(tagID: node.tag.id)
                            },
                            onDelete: {
                                pendingDeletionTagID = node.tag.id
                            }
                        )
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .refreshable {
            await store.reload()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editRequest = .create(parentID: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Новый тег")
            }

            if mode != .manage {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            expandedTagIDs.formUnion(store.tags.map(\.id))
        }
        .sheet(item: $editRequest) { request in
            NavigationStack {
                TagEditSheet(
                    title: title(for: request),
                    initialName: initialName(for: request),
                    parentTitle: parentTitle(for: request),
                    onSave: { name in
                        await saveTag(name, request: request)
                    }
                )
            }
        }
        .confirmationDialog(
            "Удалить тег?",
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Удалить ветку тегов", role: .destructive) {
                Task { await deletePendingTag() }
            }

            Button("Отмена", role: .cancel) {
                pendingDeletionTagID = nil
            }
        } message: {
            Text("Дочерние теги и привязки к вещам и контейнерам тоже будут удалены.")
        }
    }

    private var visibleNodes: [TagTreeNode] {
        flatten(tags: rootTags, depth: 0)
    }

    private var rootTags: [StorageTag] {
        sorted(store.tags.filter { $0.parentID == nil })
    }

    private var navigationTitle: String {
        switch mode {
        case .manage:
            return "Теги"
        case .selection:
            return "Выбор тегов"
        case .viewing:
            return "Иерархия тегов"
        }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { pendingDeletionTagID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionTagID = nil
                }
            }
        )
    }

    private func flatten(tags currentTags: [StorageTag], depth: Int) -> [TagTreeNode] {
        currentTags.flatMap { tag -> [TagTreeNode] in
            let children = children(of: tag)
            let isExpanded = expandedTagIDs.contains(tag.id)
            let node = TagTreeNode(
                tag: tag,
                depth: depth,
                hasChildren: !children.isEmpty,
                isExpanded: isExpanded
            )

            guard isExpanded else {
                return [node]
            }

            return [node] + flatten(tags: children, depth: depth + 1)
        }
    }

    private func children(of tag: StorageTag) -> [StorageTag] {
        sorted(store.tags.filter { $0.parentID == tag.id })
    }

    private func sorted(_ tags: [StorageTag]) -> [StorageTag] {
        tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func toggleExpansion(for tag: StorageTag) {
        if expandedTagIDs.contains(tag.id) {
            expandedTagIDs.remove(tag.id)
        } else {
            expandedTagIDs.insert(tag.id)
        }
    }

    private func toggleSelection(for tag: StorageTag) {
        guard mode == .selection else {
            return
        }

        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }

    private func tag(for id: UUID?) -> StorageTag? {
        guard let id else {
            return nil
        }

        return store.tags.first { $0.id == id }
    }

    private func title(for request: TagEditRequest) -> String {
        switch request {
        case .create:
            return "Новый тег"
        case .rename:
            return "Переименовать"
        }
    }

    private func initialName(for request: TagEditRequest) -> String {
        guard case .rename(let tagID) = request else {
            return ""
        }

        return tag(for: tagID)?.name ?? ""
    }

    private func parentTitle(for request: TagEditRequest) -> String? {
        switch request {
        case .create(let parentID):
            guard let parent = tag(for: parentID) else {
                return nil
            }

            return TagUtilities.path(for: parent, in: store.tags)

        case .rename(let tagID):
            guard let parentID = tag(for: tagID)?.parentID,
                  let parent = tag(for: parentID) else {
                return nil
            }

            return TagUtilities.path(for: parent, in: store.tags)
        }
    }

    private func saveTag(_ rawName: String, request: TagEditRequest) async -> String? {
        let name = TagUtilities.normalizedTagName(rawName)

        guard !name.isEmpty else {
            return "Введите название тега."
        }

        let editingTag: StorageTag?
        let parentID: UUID?

        switch request {
        case .create(let requestedParentID):
            editingTag = nil
            parentID = requestedParentID

        case .rename(let tagID):
            editingTag = tag(for: tagID)
            parentID = editingTag?.parentID
        }

        let duplicate = store.tags.contains {
            $0.id != editingTag?.id &&
            $0.parentID == parentID &&
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }

        guard !duplicate else {
            return "Такой тег уже есть в этой ветке."
        }

        do {
            if let editingTag {
                try await store.updateTag(editingTag, name: name)
            } else {
                let newTag = try await store.createTag(name: name, parentID: parentID)

                if let parentID {
                    expandedTagIDs.insert(parentID)
                }

                if mode == .selection {
                    selectedTagIDs.insert(newTag.id)
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func deletePendingTag() async {
        guard let pendingDeletionTagID,
              let tag = tag(for: pendingDeletionTagID) else {
            return
        }

        do {
            let tagIDs = TagUtilities.descendantIDs(of: [pendingDeletionTagID], in: store.tags)
            try await store.deleteTag(tag)
            selectedTagIDs.subtract(tagIDs)
            self.pendingDeletionTagID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TagTreeNode: Identifiable {
    let tag: StorageTag
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool

    var id: UUID {
        tag.id
    }
}

private struct TagTreeRow: View {
    let node: TagTreeNode
    let mode: TagHierarchyMode
    let isSelected: Bool
    let onToggleExpansion: () -> Void
    let onToggleSelection: () -> Void
    let onAddChild: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleExpansion) {
                Image(systemName: node.hasChildren ? chevronName : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .opacity(node.hasChildren ? 1 : 0)
            }
            .buttonStyle(.plain)
            .disabled(!node.hasChildren)

            if mode == .selection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .imageScale(.large)
            }

            Text(TagUtilities.displayName(node.tag))
                .font(.body)
                .fontWeight(mode == .viewing && isSelected ? .semibold : .regular)
                .foregroundStyle(mode == .viewing && isSelected ? .blue : .primary)
                .lineLimit(1)

            Spacer()

            if mode == .viewing && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .imageScale(.large)
            }

            Menu {
                Button {
                    onAddChild()
                } label: {
                    Label("Дочерний тег", systemImage: "plus")
                }

                Button {
                    onRename()
                } label: {
                    Label("Переименовать", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Действия с тегом")
        }
        .padding(.leading, CGFloat(node.depth) * 22)
        .contentShape(Rectangle())
        .onTapGesture {
            if mode == .selection {
                onToggleSelection()
            } else if node.hasChildren {
                onToggleExpansion()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Удалить", systemImage: "trash")
            }

            Button {
                onRename()
            } label: {
                Label("Править", systemImage: "pencil")
            }
            .tint(.blue)

            Button {
                onAddChild()
            } label: {
                Label("Дочерний", systemImage: "plus")
            }
            .tint(.green)
        }
    }

    private var chevronName: String {
        node.isExpanded ? "chevron.down" : "chevron.right"
    }
}

private enum TagEditRequest: Identifiable {
    case create(parentID: UUID?)
    case rename(tagID: UUID)

    var id: String {
        switch self {
        case .create(let parentID):
            return "create-\(parentID?.uuidString ?? "root")"
        case .rename(let tagID):
            return "rename-\(tagID.uuidString)"
        }
    }
}

private struct TagEditSheet: View {
    let title: String
    let initialName: String
    let parentTitle: String?
    let onSave: (String) async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        title: String,
        initialName: String,
        parentTitle: String?,
        onSave: @escaping (String) async -> String?
    ) {
        self.title = title
        self.initialName = initialName
        self.parentTitle = parentTitle
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        Form {
            Section("Тег") {
                TextField("Название", text: $name)
                    .textInputAutocapitalization(.never)
            }

            Section("Родитель") {
                Text(parentTitle ?? "Корневой тег")
                    .foregroundStyle(parentTitle == nil ? .secondary : .primary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Сохранение" : "Сохранить") {
                    Task { await save() }
                }
                .disabled(TagUtilities.normalizedTagName(name).isEmpty || isSaving)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        if let error = await onSave(name) {
            errorMessage = error
            return
        }

        dismiss()
    }
}
