import SwiftUI

/// The classic full-screen Launchpad: a search field, horizontally paged grid
/// of app icons, and page indicator dots.
struct LaunchpadView: View {
    @ObservedObject var model: LaunchpadModel
    let onLaunch: (AppInfo) -> Void
    let onClose: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var currentPage: Int? = 0

    private let columns = 7
    private let rows = 5
    private var pageSize: Int { columns * rows }

    var body: some View {
        let results = model.filtered
        let pages = paginate(results)

        ZStack {
            // Dim layer; tapping empty space dismisses.
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(spacing: 22) {
                searchBar

                if model.query.isEmpty {
                    pagedGrid(pages)
                    pageDots(count: pages.count)
                } else {
                    filteredGrid(results)
                }
            }
            .padding(.vertical, 54)
            .padding(.horizontal, 90)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { searchFocused = true }
        .onChange(of: model.query) { currentPage = 0 }
        .onKeyPress(.escape) {
            if model.query.isEmpty { onClose() } else { model.query = "" }
            return .handled
        }
        .onKeyPress(.return) {
            if let first = results.first { onLaunch(first) }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard model.query.isEmpty else { return .ignored }
            changePage(-1, count: pages.count); return .handled
        }
        .onKeyPress(.rightArrow) {
            guard model.query.isEmpty else { return .ignored }
            changePage(+1, count: pages.count); return .handled
        }
    }

    // MARK: - Pieces

    private var searchBar: some View {
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

    private func pagedGrid(_ pages: [[AppInfo]]) -> some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                        gridPage(page)
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

    private func gridPage(_ page: [AppInfo]) -> some View {
        VStack {
            Spacer(minLength: 0)
            LazyVGrid(columns: gridColumns, spacing: 26) {
                ForEach(page) { iconCell($0) }
            }
            Spacer(minLength: 0)
        }
    }

    private func filteredGrid(_ results: [AppInfo]) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 26) {
                ForEach(results) { iconCell($0) }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 18), count: columns)
    }

    private func iconCell(_ app: AppInfo) -> some View {
        Button {
            onLaunch(app)
        } label: {
            VStack(spacing: 7) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 74, height: 74)
                Text(app.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(radius: 2)
            }
            .frame(width: 118)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle())
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: 9) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Circle()
                    .fill(.white.opacity(i == (currentPage ?? 0) ? 0.9 : 0.32))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation(.easeInOut) { currentPage = i } }
            }
        }
        .frame(height: 12)
    }

    // MARK: - Helpers

    private func paginate(_ items: [AppInfo]) -> [[AppInfo]] {
        guard !items.isEmpty else { return [[]] }
        return stride(from: 0, to: items.count, by: pageSize).map {
            Array(items[$0..<min($0 + pageSize, items.count)])
        }
    }

    private func changePage(_ delta: Int, count: Int) {
        let next = (currentPage ?? 0) + delta
        guard next >= 0, next < count else { return }
        withAnimation(.easeInOut) { currentPage = next }
    }
}

/// Subtle scale-on-press feedback, like the real Launchpad.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
