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

    // Drag state
    @State private var dragID: String?          // item being dragged
    @State private var dragPoint: CGPoint = .zero
    @State private var folderTargetID: String?  // icon highlighted to form a folder
    @State private var pressItemID: String?     // item under the initial press
    @State private var pressClassified = false
    @State private var gapSlot: Int = 0         // page slot the dragged item will drop into
    @State private var lastHoverSlot: Int = 0
    @State private var hoverItemID: String?     // icon currently under the cursor
    @State private var dwellTimer: Timer?
    @State private var edgeTimer: Timer?
    @State private var hoverID: String?

    // Drag handed off from an open folder (classic: dragging past the folder
    // edge closes it and the drag continues over the page). The app stays in
    // the folder until the drop so the overlay never unmounts mid-gesture.
    @State private var extDragPath: String?
    @State private var gridFrame: CGRect = .zero   // pagedGrid frame, global coords

    private func flowItems() -> [LaunchItem] {
        currentPageItems.filter { $0.id != dragID }
    }

    /// Highlight behind a hovered icon so it's clear the icon is the click
    /// target (launches the app), versus empty space (closes Relaunch).
    private func hoverHighlight(_ hovering: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.white.opacity(hovering ? 0.14 : 0))
            .padding(4)
    }

    private func setHover(_ id: String, _ hovering: Bool) {
        if hovering { hoverID = id }
        else if hoverID == id { hoverID = nil }
    }

    private var columns: Int { model.columns }
    private var rows: Int { model.rows }
    private var pageSize: Int { model.pageSize }

    // Columns fill the available width; row height scales with the icon size.
    private var cellH: CGFloat { model.iconSize + 64 }
    private func cellW(_ size: CGSize) -> CGFloat { size.width / CGFloat(columns) }

    // Compact hover/click target around the icon (not the whole wide cell), so
    // the gaps between icons close Relaunch rather than launching an app.
    private var hitWidth: CGFloat { model.iconSize + 44 }
    private var hitHeight: CGFloat { model.iconSize + 42 }
    private func gridOrigin(_ size: CGSize) -> CGPoint { CGPoint(x: 0, y: 8) }

    private var pages: [[LaunchItem]] { paginate(model.items) }
    private var currentPageItems: [LaunchItem] {
        let p = pages
        return p.indices.contains(model.currentPage) ? p[model.currentPage] : []
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
                FolderOverlay(model: model, folderID: id, onLaunch: { onLaunch($0) },
                              onDragOut: { path, global in beginFolderDragOut(path, at: global) },
                              onDragOutMoved: { global in
                                  dragPoint = toGrid(global)
                                  handleDragMove(dragPoint, size: gridFrame.size)
                              },
                              onDragOutEnded: { endFolderDragOut(folderID: id) })
            }
        }
        .background(VisualEffectView().ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear { searchFocused = true }
        .onChange(of: model.query) {
            // Typing swaps the grid for search results, tearing the drag
            // gesture down without onEnded — drop any in-flight drag state.
            resetDragState()
            model.currentPage = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Re-opening after ⌘-Tab (window closes mid-drag): clear leftovers.
            resetDragState()
        }
        .onKeyPress(.escape) {
            resetDragState()
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
                TextField("Search", text: $model.query)
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
            .help("Settings")
        }
    }

    // MARK: - Paged grid (custom drag)

    private var pagedGrid: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Current page only (no spill); pages slide horizontally in/out.
                pageGridView(currentPageItems, pageIndex: model.currentPage, size: geo.size)
                    .id(model.currentPage)
                    .transition(.asymmetric(
                        insertion: .move(edge: model.lastPageDir >= 0 ? .trailing : .leading),
                        removal: .move(edge: model.lastPageDir >= 0 ? .leading : .trailing)))

                // Floating dragged icon follows the cursor.
                if let id = dragID, let item = model.items.first(where: { $0.id == id }) {
                    cellView(item)
                        .frame(width: cellW(geo.size), height: cellH)
                        .scaleEffect(1.18)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        .position(dragPoint)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .clipped()
            .coordinateSpace(name: "gridRoot")
            .gesture(gridGesture(size: geo.size))
            .background(GeometryReader { g -> Color in
                let f = g.frame(in: .global)
                if gridFrame != f { DispatchQueue.main.async { gridFrame = f } }
                return Color.clear
            })
        }
    }

    private func pageGridView(_ pageItems: [LaunchItem], pageIndex: Int, size: CGSize) -> some View {
        let origin = gridOrigin(size)
        let cw = cellW(size)
        // The dragged icon floats, so remove it from whichever page holds it;
        // the gap marking its drop slot shows only on the page being viewed.
        let display = dragID != nil ? pageItems.filter { $0.id != dragID } : pageItems
        let gap = (dragID != nil && pageIndex == model.currentPage) ? gapSlot : -1
        return ZStack(alignment: .topLeading) {
            ForEach(Array(display.enumerated()), id: \.element.id) { idx, item in
                let slot = (gap >= 0 && idx >= gap) ? idx + 1 : idx
                let col = slot % columns, row = slot / columns
                let hovering = hoverID == item.id && dragID == nil
                cellView(item)
                    .frame(width: hitWidth, height: hitHeight)
                    .background(hoverHighlight(hovering))
                    .scaleEffect(item.id == folderTargetID ? 1.14 : (hovering ? 1.06 : 1))
                    .onHover { setHover(item.id, $0) }
                    .frame(width: cw, height: cellH)
                    .position(x: origin.x + cw * (CGFloat(col) + 0.5),
                              y: origin.y + cellH * (CGFloat(row) + 0.5))
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: slot)
                    .animation(.easeOut(duration: 0.12), value: hovering)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

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
                if dragID == nil && moved {
                    dragID = item
                    let slot = currentPageItems.firstIndex(where: { $0.id == item }) ?? 0
                    gapSlot = slot
                    lastHoverSlot = slot
                    hoverItemID = nil
                }
                if dragID != nil {
                    dragPoint = value.location
                    handleDragMove(value.location, size: size)
                }
            }
            .onEnded { value in
                defer { pressItemID = nil; pressClassified = false }
                if let item = pressItemID {
                    if dragID != nil {
                        handleDragEnd()
                    } else {
                        // Launch only on a clean click — any movement (even a
                        // fast flick onChanged didn't latch as a drag) is not a tap.
                        let moved = abs(value.translation.width) > 6 || abs(value.translation.height) > 6
                        if !moved { tap(item) }
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
        let origin = gridOrigin(size)
        let cw = cellW(size)
        let lx = point.x - origin.x, ly = point.y - origin.y
        guard lx >= 0, ly >= 0,
              lx <= CGFloat(columns) * cw, ly <= CGFloat(rows) * cellH else { return nil }
        let col = min(max(Int(lx / cw), 0), columns - 1)
        let row = min(max(Int(ly / cellH), 0), rows - 1)
        let idx = row * columns + col
        let items = currentPageItems
        guard idx < items.count else { return nil }
        // Only count presses on the compact icon target, so the gaps between
        // icons still close the Launchpad.
        let cx = cw * (CGFloat(col) + 0.5), cy = cellH * (CGFloat(row) + 0.5)
        guard abs(lx - cx) < hitWidth / 2, abs(ly - cy) < hitHeight / 2 else { return nil }
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
        let origin = gridOrigin(size)
        let cw = cellW(size)
        let lx = point.x - origin.x, ly = point.y - origin.y

        // Edge → flip page.
        let edge: CGFloat = 64
        if point.x < edge { startEdgeFlip(forward: false) }
        else if point.x > size.width - edge { startEdgeFlip(forward: true) }
        else { stopEdgeFlip() }

        let flow = flowItems()
        let col = min(max(Int(lx / cw), 0), columns - 1)
        let row = min(max(Int(ly / cellH), 0), rows - 1)
        let s = min(max(row * columns + col, 0), flow.count)

        if s == gapSlot {                      // cursor over the gap itself
            hoverItemID = nil; cancelDwell(); return
        }
        if s >= flow.count {                   // trailing empty area → drop at the end
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { gapSlot = flow.count }
            lastHoverSlot = flow.count; hoverItemID = nil; cancelDwell(); return
        }
        let flowIdx = s < gapSlot ? s : s - 1
        guard flowIdx >= 0, flowIdx < flow.count else { hoverItemID = nil; cancelDwell(); return }

        let hover = flow[flowIdx]
        guard hover.id != hoverItemID else { return }   // same icon — keep dwelling

        // Moved onto a new icon: the one we just left slides into the trailing
        // gap (reorder), and we begin a fresh dwell on the new icon.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { gapSlot = lastHoverSlot }
        lastHoverSlot = s
        hoverItemID = hover.id
        folderTargetID = nil
        if dragID.hasPrefix("app:") { scheduleDwell(hover.id) }   // only apps form folders
    }

    private func handleDragEnd() {
        stopEdgeFlip()
        dwellTimer?.invalidate(); dwellTimer = nil
        if let target = folderTargetID, let src = dragID {
            withAnimation { model.makeOrJoinFolder(draggingID: src, targetID: target) }
        } else if let src = dragID {
            // Absolute index of the gap on the page being viewed. moveItem(toIndex:)
            // removes the source first and inserts here, which keeps cross-page
            // drops on the viewed page — a by-anchor insert would land one slot
            // earlier (end of the previous page) once the source is removed.
            let target = model.currentPage * pageSize + gapSlot
            withAnimation { model.moveItem(id: src, toIndex: target) }
            model.commitLayout()
        }
        dragID = nil
        folderTargetID = nil
        hoverItemID = nil
    }

    /// Clear all drag state. Needed when the drag is orphaned mid-flight (the
    /// gesture's view is torn down without onEnded): Escape, typing into
    /// search, or the window closing under the drag. Without this, the stale
    /// dragID makes the next click move the old item instead of launching.
    private func resetDragState() {
        guard dragID != nil || extDragPath != nil || pressItemID != nil else { return }
        stopEdgeFlip()
        dwellTimer?.invalidate(); dwellTimer = nil
        dragID = nil
        extDragPath = nil
        folderTargetID = nil
        hoverItemID = nil
        pressItemID = nil
        pressClassified = false
    }

    // MARK: - Drag handed off from an open folder

    private func toGrid(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - gridFrame.minX, y: global.y - gridFrame.minY)
    }

    /// The drag crossed the folder edge: take over gap/reflow/edge-flip on the
    /// page. The model is not touched yet — the app leaves its folder on drop.
    private func beginFolderDragOut(_ path: String, at global: CGPoint) {
        extDragPath = path
        dragID = "app:" + path
        gapSlot = flowItems().count          // open a gap at the end of the page
        lastHoverSlot = gapSlot
        hoverItemID = nil
        folderTargetID = nil
        dragPoint = toGrid(global)
        handleDragMove(dragPoint, size: gridFrame.size)
    }

    private func endFolderDragOut(folderID: String) {
        guard let path = extDragPath else { return }
        stopEdgeFlip()
        dwellTimer?.invalidate(); dwellTimer = nil
        model.removeFromFolder(folderID, path)   // puts the app back on the grid
        let id = "app:" + path
        if let target = folderTargetID {
            withAnimation { model.makeOrJoinFolder(draggingID: id, targetID: target) }
        } else {
            // Same slot math as handleDragEnd: gapSlot indexes the page flow
            // without the dragged item, which is exactly the array moveItem
            // sees after removing the source.
            let target = model.currentPage * pageSize + gapSlot
            withAnimation { model.moveItem(id: id, toIndex: target) }
            model.commitLayout()
        }
        dragID = nil; folderTargetID = nil; hoverItemID = nil; extDragPath = nil
        model.openFolderID = nil
    }

    private func scheduleDwell(_ id: String) {
        dwellTimer?.invalidate()
        // .common mode so it fires while the mouse is held (event-tracking mode).
        let timer = Timer(timeInterval: 0.35, repeats: false) { _ in
            if hoverItemID == id { withAnimation { folderTargetID = id } }
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    private func cancelDwell() {
        dwellTimer?.invalidate(); dwellTimer = nil
        if folderTargetID != nil { withAnimation { folderTargetID = nil } }
    }

    private func startEdgeFlip(forward: Bool) {
        guard dragID != nil, edgeTimer == nil else { return }
        // .common mode so it fires during the drag (event-tracking run loop).
        let timer = Timer(timeInterval: 0.7, repeats: true) { _ in
            flipDuringDrag(forward: forward)
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeTimer = timer
    }

    private func stopEdgeFlip() {
        edgeTimer?.invalidate(); edgeTimer = nil
    }

    private func flipDuringDrag(forward: Bool) {
        let next = model.currentPage + (forward ? 1 : -1)
        guard next >= 0, next < pages.count, dragID != nil else { return }
        withAnimation(.easeInOut) { model.setPage(next) }
        // Reset the gap to the start of the new page; the icon stays floating.
        gapSlot = 0; lastHoverSlot = 0; hoverItemID = nil; folderTargetID = nil
    }

    // MARK: - Search results

    private func searchGrid(_ results: [AppInfo]) -> some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: columns),
                      spacing: 26) {
                ForEach(results) { app in
                    let hovering = hoverID == app.id
                    appIcon(app)
                        .frame(width: hitWidth, height: hitHeight)
                        .background(hoverHighlight(hovering))
                        .scaleEffect(hovering ? 1.06 : 1)
                        .contentShape(Rectangle())
                        .onHover { setHover(app.id, $0) }
                        .animation(.easeOut(duration: 0.12), value: hovering)
                        .onTapGesture { onLaunch(app) }
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
                .frame(width: model.iconSize, height: model.iconSize)
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
            .frame(width: model.iconSize, height: model.iconSize)
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
                    .fill(.white.opacity(i == model.currentPage ? 0.9 : 0.32))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation(.easeInOut) { model.setPage(i) } }
            }
        }
        .frame(height: 12)
    }

    private func changePage(_ delta: Int) {
        withAnimation(.easeInOut) { model.changePage(delta) }
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
    // Classic drag-out: crossing the folder edge closes the folder and hands
    // the drag to the page grid. Locations are in global coordinates.
    let onDragOut: (String, CGPoint) -> Void
    let onDragOutMoved: (CGPoint) -> Void
    let onDragOutEnded: () -> Void

    @State private var name: String = ""
    @FocusState private var nameFocused: Bool

    @State private var dragPath: String?
    @State private var dragPoint: CGPoint = .zero
    @State private var panelFrame: CGRect = .zero
    @State private var gridFrame: CGRect = .zero
    @State private var rootOrigin: CGPoint = .zero   // folderRoot origin, global
    @State private var draggedOut = false
    @State private var gapSlot = 0
    @State private var lastHoverSlot = 0
    @State private var hoverPath: String?
    @State private var pressPath: String?
    @State private var pressClassified = false
    @State private var hoverHL: String?

    private let columns = 6
    private let cellW: CGFloat = 115
    private let cellH: CGFloat = 106

    var body: some View {
        ZStack {
            // Kept mounted (faded out) during a drag-out so the active drag
            // gesture — which dies with its view — survives until the drop.
            Color.black.opacity(draggedOut ? 0 : 0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if dragPath == nil { model.openFolderID = nil } }

            if let folder = model.folder(folderID) {
                VStack(spacing: 18) {
                    TextField("Folder Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .focused($nameFocused)
                        .frame(maxWidth: 320)
                        .onSubmit { commitName() }
                        .onChange(of: nameFocused) { if !nameFocused { commitName() } }

                    folderGrid(folder)
                }
                .padding(34)
                .frame(maxWidth: 760)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .background(GeometryReader { g -> Color in
                    let f = g.frame(in: .named("folderRoot"))
                    DispatchQueue.main.async { panelFrame = f }
                    return Color.clear
                })
                .opacity(draggedOut ? 0 : 1)
                .scaleEffect(draggedOut ? 0.9 : 1)
                .onAppear { name = folder.name }
                // Escape / tapping the dim background closes the overlay before
                // any focus change fires — commit the typed name on teardown.
                .onDisappear { commitName() }
            }

            // Floating dragged icon (page-sized once it has left the folder).
            if let path = dragPath, let app = model.app(path) {
                let side: CGFloat = draggedOut ? model.iconSize : 70
                Image(nsImage: app.icon).resizable().interpolation(.high)
                    .frame(width: side, height: side)
                    .scaleEffect(1.12)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
                    .position(dragPoint)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "folderRoot")
        .background(GeometryReader { g -> Color in
            let o = g.frame(in: .global).origin
            if rootOrigin != o { DispatchQueue.main.async { rootOrigin = o } }
            return Color.clear
        })
        .environment(\.colorScheme, .dark)
    }

    private func toGlobal(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + rootOrigin.x, y: p.y + rootOrigin.y)
    }

    private func folderGrid(_ folder: Folder) -> some View {
        let all = folder.appPaths
        let rows = max(1, (all.count + columns - 1) / columns)
        let dragging = dragPath != nil
        let display = dragging ? all.filter { $0 != dragPath } : all
        let gap = dragging ? gapSlot : -1
        return ZStack(alignment: .topLeading) {
            ForEach(Array(display.enumerated()), id: \.element) { idx, path in
                let slot = (gap >= 0 && idx >= gap) ? idx + 1 : idx
                let col = slot % columns, row = slot / columns
                if let app = model.app(path) {
                    let hovering = hoverHL == path && dragPath == nil
                    folderIcon(app, path: path)
                        .frame(width: 98, height: 98)
                        .background(RoundedRectangle(cornerRadius: 18)
                            .fill(.white.opacity(hovering ? 0.14 : 0)).padding(4))
                        .scaleEffect(hovering ? 1.06 : 1)
                        .onHover { if $0 { hoverHL = path } else if hoverHL == path { hoverHL = nil } }
                        .frame(width: cellW, height: cellH)
                        .position(x: cellW * (CGFloat(col) + 0.5), y: cellH * (CGFloat(row) + 0.5))
                        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: slot)
                        .animation(.easeOut(duration: 0.12), value: hovering)
                }
            }
        }
        .frame(width: CGFloat(columns) * cellW, height: CGFloat(rows) * cellH)
        .background(GeometryReader { g -> Color in
            let f = g.frame(in: .named("folderRoot"))
            DispatchQueue.main.async { gridFrame = f }
            return Color.clear
        })
        .contentShape(Rectangle())
        .gesture(folderDrag(folder))
    }

    private func folderIcon(_ app: AppInfo, path: String) -> some View {
        VStack(spacing: 7) {
            Image(nsImage: app.icon).resizable().interpolation(.high)
                .frame(width: 70, height: 70)
            Text(app.name).font(.system(size: 12)).foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
        }
        .contextMenu {
            Button("Remove from Folder") { model.removeFromFolder(folderID, path) }
        }
    }

    private func folderDrag(_ folder: Folder) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("folderRoot"))
            .onChanged { value in
                if !pressClassified {
                    pressClassified = true
                    pressPath = hitFolder(value.startLocation, folder: folder)
                }
                guard let path = pressPath else { return }
                let moved = abs(value.translation.width) > 6 || abs(value.translation.height) > 6
                if dragPath == nil && moved {
                    dragPath = path
                    let slot = folder.appPaths.firstIndex(of: path) ?? 0
                    gapSlot = slot; lastHoverSlot = slot; hoverPath = nil
                }
                if dragPath != nil {
                    dragPoint = value.location
                    if draggedOut {
                        onDragOutMoved(toGlobal(value.location))
                    } else if !panelFrame.contains(value.location) {
                        // Crossed the folder edge: close the folder and hand
                        // the drag to the page grid, like classic Launchpad.
                        withAnimation(.easeOut(duration: 0.18)) { draggedOut = true }
                        onDragOut(path, toGlobal(value.location))
                    } else {
                        folderMove(value.location, folder: folder)
                    }
                }
            }
            .onEnded { value in
                defer { pressPath = nil; pressClassified = false; draggedOut = false }
                guard let path = pressPath else { return }
                if dragPath == nil {
                    let moved = abs(value.translation.width) > 6 || abs(value.translation.height) > 6
                    if !moved, let app = model.app(path) { onLaunch(app) }
                } else if draggedOut {
                    onDragOutEnded()                         // page grid finalizes the drop
                } else if !panelFrame.contains(value.location) {
                    model.removeFromFolder(folderID, path)   // dropped outside → leave folder
                    model.openFolderID = nil
                } else {
                    model.moveInFolder(folderID, move: path, toIndex: gapSlot)
                }
                dragPath = nil; hoverPath = nil
            }
    }

    private func hitFolder(_ point: CGPoint, folder: Folder) -> String? {
        let lx = point.x - gridFrame.minX, ly = point.y - gridFrame.minY
        guard lx >= 0, ly >= 0 else { return nil }
        let col = min(max(Int(lx / cellW), 0), columns - 1)
        let row = max(Int(ly / cellH), 0)
        let idx = row * columns + col
        guard idx < folder.appPaths.count else { return nil }
        let cx = cellW * (CGFloat(col) + 0.5), cy = cellH * (CGFloat(row) + 0.5)
        guard abs(lx - cx) < 49, abs(ly - cy) < 49 else { return nil }   // compact icon target
        return folder.appPaths[idx]
    }

    private func folderMove(_ point: CGPoint, folder: Folder) {
        let lx = point.x - gridFrame.minX, ly = point.y - gridFrame.minY
        let flow = folder.appPaths.filter { $0 != dragPath }
        let col = min(max(Int(lx / cellW), 0), columns - 1)
        let row = max(Int(ly / cellH), 0)
        let s = min(max(row * columns + col, 0), flow.count)
        if s == gapSlot { hoverPath = nil; return }
        if s >= flow.count {                   // trailing empty area → drop at the end
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { gapSlot = flow.count }
            lastHoverSlot = flow.count; hoverPath = nil; return
        }
        let flowIdx = s < gapSlot ? s : s - 1
        guard flowIdx >= 0, flowIdx < flow.count else { hoverPath = nil; return }
        let hover = flow[flowIdx]
        guard hover != hoverPath else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { gapSlot = lastHoverSlot }
        lastHoverSlot = s
        hoverPath = hover
    }

    private func commitName() {
        model.renameFolder(folderID, name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
