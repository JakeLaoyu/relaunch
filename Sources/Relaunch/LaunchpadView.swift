import SwiftUI

/// Classic full-screen Launchpad with a custom (gesture-driven) drag system —
/// press an icon and it follows the cursor, others reflow live, hovering over
/// another icon forms a folder, and dragging to the screen edge flips pages.
struct LaunchpadView: View {
    @ObservedObject var model: LaunchpadModel
    let onLaunch: (AppInfo) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var currentPage = 0

    // Drag state
    @State private var dragID: String?          // item being dragged
    @State private var dragPoint: CGPoint = .zero
    @State private var folderTargetID: String?  // icon highlighted to form a folder
    @State private var pressItemID: String?     // item under the initial press
    @State private var pressClassified = false
    @State private var dwellTargetID: String?
    @State private var dwellTimer: Timer?
    @State private var edgeTimer: Timer?

    private let columns = 7
    private let rows = 5
    private var pageSize: Int { columns * rows }

    private var pages: [[LaunchItem]] { paginate(model.items) }
    private var currentPageItems: [LaunchItem] {
        let p = pages
        return p.indices.contains(currentPage) ? p[currentPage] : []
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if dragID == nil { onClose() } }

            VStack(spacing: 22) {
                searchBar
                if model.query.isEmpty {
                    pagedGrid
                    pageDots(count: pages.count)
                } else {
                    searchGrid(model.searchResults)
                }
            }
            .padding(.vertical, 54)
            .padding(.horizontal, 90)

            if let id = model.openFolderID {
                FolderOverlay(model: model, folderID: id, onLaunch: { onLaunch($0) })
            }
        }
        .background(VisualEffectView().ignoresSafeArea())
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

    // MARK: - Paged grid (custom drag)

    private var pagedGrid: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, pageItems in
                        pageGridView(pageItems, size: geo.size)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(x: -CGFloat(currentPage) * geo.size.width)
                .animation(.easeInOut(duration: 0.25), value: currentPage)

                // Floating dragged icon follows the cursor.
                if let id = dragID, let item = model.items.first(where: { $0.id == id }) {
                    cellView(item)
                        .frame(width: cellW(geo.size), height: cellH(geo.size))
                        .scaleEffect(1.18)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        .position(dragPoint)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .coordinateSpace(name: "gridRoot")
            .gesture(gridGesture(size: geo.size))
        }
    }

    private func pageGridView(_ pageItems: [LaunchItem], size: CGSize) -> some View {
        let cw = cellW(size), ch = cellH(size)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(pageItems.enumerated()), id: \.element.id) { idx, item in
                let col = idx % columns, row = idx / columns
                Group {
                    if item.id == dragID {
                        Color.clear.frame(width: cw, height: ch)   // gap left by the dragged icon
                    } else {
                        cellView(item)
                            .frame(width: cw, height: ch)
                            .scaleEffect(item.id == folderTargetID ? 1.14 : 1)
                    }
                }
                .position(x: cw * (CGFloat(col) + 0.5), y: ch * (CGFloat(row) + 0.5))
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: idx)
            }
        }
    }

    private func cellW(_ size: CGSize) -> CGFloat { size.width / CGFloat(columns) }
    private func cellH(_ size: CGSize) -> CGFloat { size.height / CGFloat(rows) }

    @ViewBuilder
    private func cellView(_ item: LaunchItem) -> some View {
        switch item {
        case .app(let path):
            if let app = model.app(path) { appIcon(app) }
        case .folder(let folder):
            folderIcon(folder)
        }
    }

    // MARK: - Drag gesture

    private func gridGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gridRoot"))
            .onChanged { value in
                if !pressClassified {
                    pressClassified = true
                    pressItemID = hitTest(value.startLocation, size: size)
                }
                guard let item = pressItemID else { return }   // background drag
                let moved = abs(value.translation.width) > 6 || abs(value.translation.height) > 6
                if dragID == nil && moved { dragID = item }
                if dragID != nil {
                    dragPoint = value.location
                    handleDragMove(value.location, size: size)
                }
            }
            .onEnded { value in
                defer { pressItemID = nil; pressClassified = false }
                if let item = pressItemID {
                    if dragID == nil {
                        tap(item)                  // click without dragging
                    } else {
                        handleDragEnd()
                    }
                } else {
                    let tx = value.translation.width
                    if abs(tx) < 10 && abs(value.translation.height) < 10 { onClose() }
                    else if tx <= -40 { changePage(+1) }
                    else if tx >= 40 { changePage(-1) }
                }
            }
    }

    private func hitTest(_ point: CGPoint, size: CGSize) -> String? {
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }
        let cw = cellW(size), ch = cellH(size)
        let col = min(max(Int(point.x / cw), 0), columns - 1)
        let row = min(max(Int(point.y / ch), 0), rows - 1)
        let idx = row * columns + col
        let items = currentPageItems
        guard idx < items.count else { return nil }
        // Only count presses near the icon, so gaps still close the Launchpad.
        let cx = cw * (CGFloat(col) + 0.5), cy = ch * (CGFloat(row) + 0.5)
        guard abs(point.x - cx) < cw * 0.42, abs(point.y - cy) < ch * 0.46 else { return nil }
        return items[idx].id
    }

    private func tap(_ id: String) {
        guard let item = model.items.first(where: { $0.id == id }) else { return }
        switch item {
        case .app(let path): if let app = model.app(path) { onLaunch(app) }
        case .folder(let folder): model.openFolderID = folder.id
        }
    }

    private func handleDragMove(_ point: CGPoint, size: CGSize) {
        guard let dragID else { return }
        let cw = cellW(size), ch = cellH(size)
        let col = min(max(Int(point.x / cw), 0), columns - 1)
        let row = min(max(Int(point.y / ch), 0), rows - 1)
        let items = currentPageItems
        let localIdx = min(row * columns + col, max(items.count - 1, 0))

        // Edge → flip page.
        let edge: CGFloat = 64
        if point.x < edge { startEdgeFlip(forward: false) }
        else if point.x > size.width - edge { startEdgeFlip(forward: true) }
        else { stopEdgeFlip() }

        guard localIdx < items.count else { cancelDwell(); return }
        let target = items[localIdx]
        let cx = cw * (CGFloat(col) + 0.5), cy = ch * (CGFloat(row) + 0.5)
        let overCenter = abs(point.x - cx) < cw * 0.30 && abs(point.y - cy) < ch * 0.32
        let draggingIsApp = dragID.hasPrefix("app:")

        if overCenter, target.id != dragID, draggingIsApp {
            // Hover over another icon's center → after a short dwell, form a folder.
            if dwellTargetID != target.id {
                dwellTargetID = target.id
                scheduleDwell(target.id)
            }
        } else {
            cancelDwell()
            if folderTargetID == nil {
                let globalIdx = currentPage * pageSize + localIdx
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    model.moveItem(id: dragID, toIndex: globalIdx)
                }
            }
        }
    }

    private func handleDragEnd() {
        stopEdgeFlip()
        dwellTimer?.invalidate(); dwellTimer = nil
        if let target = folderTargetID, let src = dragID {
            withAnimation { model.makeOrJoinFolder(draggingID: src, targetID: target) }
        } else {
            model.commitLayout()
        }
        dragID = nil
        folderTargetID = nil
        dwellTargetID = nil
    }

    private func scheduleDwell(_ id: String) {
        dwellTimer?.invalidate()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in
            withAnimation { folderTargetID = id }
        }
    }

    private func cancelDwell() {
        dwellTimer?.invalidate(); dwellTimer = nil
        dwellTargetID = nil
        if folderTargetID != nil { withAnimation { folderTargetID = nil } }
    }

    private func startEdgeFlip(forward: Bool) {
        guard dragID != nil, edgeTimer == nil else { return }
        edgeTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            flipDuringDrag(forward: forward)
        }
    }

    private func stopEdgeFlip() {
        edgeTimer?.invalidate(); edgeTimer = nil
    }

    private func flipDuringDrag(forward: Bool) {
        let pageCount = pages.count
        let next = currentPage + (forward ? 1 : -1)
        guard next >= 0, next < pageCount, let id = dragID else { return }
        withAnimation(.easeInOut) {
            currentPage = next
            model.moveItem(id: id, toIndex: next * pageSize)   // carry the icon to the new page
        }
    }

    // MARK: - Search results

    private func searchGrid(_ results: [AppInfo]) -> some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: columns),
                      spacing: 26) {
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

    // MARK: - Icon views

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
                RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.18))
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

    // MARK: - Pages / dots

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
                    .fill(.white.opacity(i == currentPage ? 0.9 : 0.32))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation(.easeInOut) { currentPage = i } }
            }
        }
        .frame(height: 12)
    }

    private func changePage(_ delta: Int) {
        let next = currentPage + delta
        guard next >= 0, next < pages.count else { return }
        withAnimation(.easeInOut) { currentPage = next }
    }
}

/// Dark blurred desktop background (`NSVisualEffectView` bridged to SwiftUI).
private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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
    }

    private func commitName() {
        model.renameFolder(folderID, name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
