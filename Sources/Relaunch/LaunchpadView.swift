import SwiftUI
import UniformTypeIdentifiers

/// The classic full-screen Launchpad: search field, horizontally paged grid of
/// app icons and folders, page dots, plus drag-to-rearrange and folders.
struct LaunchpadView: View {
    @ObservedObject var model: LaunchpadModel
    let onLaunch: (AppInfo) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var currentPage: Int? = 0
    @State private var edgeTimer: Timer?

    private let columns = 7
    private let cellWidth: CGFloat = 118
    private var pageSize: Int { columns * 5 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(spacing: 22) {
                searchBar
                if model.query.isEmpty {
                    let pages = paginate(model.items)
                    pagedGrid(pages)
                    pageDots(count: pages.count)
                } else {
                    searchGrid(model.searchResults)
                }
            }
            .padding(.vertical, 54)
            .padding(.horizontal, 90)

            // Drag an icon to the left/right gutter to flip pages.
            if model.query.isEmpty && model.openFolderID == nil {
                HStack {
                    edgeFlipZone(forward: false)
                    Spacer()
                    edgeFlipZone(forward: true)
                }
            }

            if let id = model.openFolderID {
                FolderOverlay(model: model, folderID: id,
                              onLaunch: { app in onLaunch(app) })
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { searchFocused = true }
        .onChange(of: model.query) { currentPage = 0 }
        .onKeyPress(.escape) {
            if model.openFolderID != nil { model.openFolderID = nil }
            else if !model.query.isEmpty { model.query = "" }
            else { onClose() }
            return .handled
        }
        .onKeyPress(.return) {
            if let first = model.searchResults.first { onLaunch(first) }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard model.query.isEmpty, model.openFolderID == nil else { return .ignored }
            changePage(-1); return .handled
        }
        .onKeyPress(.rightArrow) {
            guard model.query.isEmpty, model.openFolderID == nil else { return .ignored }
            changePage(+1); return .handled
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.7))
                TextField("搜索", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        // "More" button pinned to the far right of the search row.
        .overlay(alignment: .trailing) {
            Button(action: onOpenSettings) {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    // MARK: - Grids

    private func pagedGrid(_ pages: [[LaunchItem]]) -> some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, pageItems in
                        gridPage(pageItems)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(idx)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentPage)
            .scrollIndicators(.hidden)
        }
    }

    private func gridPage(_ items: [LaunchItem]) -> some View {
        VStack(spacing: 0) {
            // Top-aligned: a partial last page keeps the same row positions as
            // full pages instead of being vertically centered.
            LazyVGrid(columns: gridColumns, spacing: 26) {
                ForEach(items) { itemCell($0) }
            }
            .padding(.top, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
    }

    private func searchGrid(_ results: [AppInfo]) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 26) {
                ForEach(results) { app in
                    appIcon(app).onTapGesture { onLaunch(app) }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 18), count: columns)
    }

    // MARK: - Cells

    @ViewBuilder
    private func itemCell(_ item: LaunchItem) -> some View {
        cellContent(item)
            .frame(width: cellWidth)
            .draggable(payload(for: item)) { dragPreview(item) }
            .dropDestination(for: String.self) { dropped, location in
                guard let payload = dropped.first else { return false }
                let zone = zone(for: location, isFolder: item.isFolder)
                model.performDrop(payload: payload, targetID: item.id, zone: zone)
                return true
            }
    }

    @ViewBuilder
    private func cellContent(_ item: LaunchItem) -> some View {
        switch item {
        case .app(let path):
            if let app = model.app(path) {
                appIcon(app).onTapGesture { onLaunch(app) }
            }
        case .folder(let folder):
            folderIcon(folder).onTapGesture { model.openFolderID = folder.id }
        }
    }

    private func appIcon(_ app: AppInfo) -> some View {
        VStack(spacing: 7) {
            Image(nsImage: app.icon)
                .resizable().interpolation(.high)
                .frame(width: 74, height: 74)
            label(app.name)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func folderIcon(_ folder: Folder) -> some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.18))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                          spacing: 4) {
                    ForEach(model.previewIcons(folder)) { app in
                        Image(nsImage: app.icon).resizable().interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .padding(10)
            }
            .frame(width: 74, height: 74)
            label(folder.name)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .shadow(radius: 2)
    }

    @ViewBuilder
    private func dragPreview(_ item: LaunchItem) -> some View {
        switch item {
        case .app(let path):
            if let app = model.app(path) {
                Image(nsImage: app.icon).resizable().frame(width: 74, height: 74)
            }
        case .folder(let folder):
            folderIcon(folder).frame(width: cellWidth)
        }
    }

    // MARK: - Drag/drop helpers

    private func payload(for item: LaunchItem) -> String {
        switch item {
        case .app(let path): return "T|app|" + path
        case .folder(let f): return "T|folder|" + f.id
        }
    }

    /// Left/right third → reorder before/after; center → drop onto (folder).
    private func zone(for location: CGPoint, isFolder: Bool) -> DropZone {
        let x = location.x
        if x < cellWidth * 0.33 { return .before }
        if x > cellWidth * 0.67 { return .after }
        return .onto
    }

    // MARK: - Pages / misc

    private func paginate(_ items: [LaunchItem]) -> [[LaunchItem]] {
        guard !items.isEmpty else { return [[]] }
        return Swift.stride(from: 0, to: items.count, by: pageSize).map {
            Array(items[$0..<Swift.min($0 + pageSize, items.count)])
        }
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: 9) {
            ForEach(0..<Swift.max(count, 1), id: \.self) { i in
                Circle()
                    .fill(.white.opacity(i == (currentPage ?? 0) ? 0.9 : 0.32))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation(.easeInOut) { currentPage = i } }
            }
        }
        .frame(height: 12)
    }

    private func changePage(_ delta: Int) {
        let pages = paginate(model.items).count
        let next = (currentPage ?? 0) + delta
        guard next >= 0, next < pages else { return }
        withAnimation(.easeInOut) { currentPage = next }
    }

    // MARK: - Cross-page drag

    /// A gutter strip that auto-flips pages while a drag hovers over it. The
    /// drop itself isn't consumed here — the user releases onto a real cell on
    /// the page they flipped to.
    private func edgeFlipZone(forward: Bool) -> some View {
        Color.clear
            .frame(width: 70)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onClose() }
            .dropDestination(for: String.self) { _, _ in
                false
            } isTargeted: { targeted in
                if targeted { startEdgeFlip(forward: forward) } else { stopEdgeFlip() }
            }
    }

    private func startEdgeFlip(forward: Bool) {
        stopEdgeFlip()
        edgeTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            changePage(forward ? 1 : -1)
        }
    }

    private func stopEdgeFlip() {
        edgeTimer?.invalidate()
        edgeTimer = nil
    }
}

// MARK: - Folder overlay

private struct FolderOverlay: View {
    @ObservedObject var model: LaunchpadModel
    let folderID: String
    let onLaunch: (AppInfo) -> Void

    @State private var name: String = ""
    @FocusState private var nameFocused: Bool

    private let columns = 6

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.openFolderID = nil }

            if let folder = model.folder(folderID) {
                VStack(spacing: 18) {
                    TextField("文件夹名称", text: $name)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .focused($nameFocused)
                        .frame(maxWidth: 320)
                        .onSubmit { commitName() }
                        .onChange(of: nameFocused) { if !nameFocused { commitName() } }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18),
                                             count: columns), spacing: 22) {
                        ForEach(folder.appPaths, id: \.self) { path in
                            if let app = model.app(path) {
                                folderApp(app, path: path, folderID: folder.id)
                            }
                        }
                    }
                }
                .padding(34)
                .frame(maxWidth: 760)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .onAppear { name = folder.name }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func folderApp(_ app: AppInfo, path: String, folderID: String) -> some View {
        VStack(spacing: 7) {
            Image(nsImage: app.icon).resizable().interpolation(.high)
                .frame(width: 70, height: 70)
            Text(app.name).font(.system(size: 12)).foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(width: 108)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onLaunch(app) }
        .contextMenu {
            Button("移出文件夹") { model.removeFromFolder(folderID, path) }
        }
        .draggable("F|" + folderID + "|" + path) {
            Image(nsImage: app.icon).resizable().frame(width: 70, height: 70)
        }
        .dropDestination(for: String.self) { dropped, location in
            guard let payload = dropped.first else { return false }
            let zone: DropZone = location.x < 54 ? .before : .after
            // Reorder within the folder only when the source is from this folder.
            if payload.hasPrefix("F|" + folderID + "|") {
                let src = String(payload.dropFirst(("F|" + folderID + "|").count))
                model.reorderInFolder(folderID, move: src, target: path, zone: zone)
            } else {
                model.addToFolder(folderID, payload: payload)
            }
            return true
        }
    }

    private func commitName() {
        model.renameFolder(folderID, name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
