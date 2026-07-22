import SwiftUI

/// A user-added widget on the Create canvas: a feature, sized in a 4-column grid.
struct CreateTile: Codable, Identifiable, Hashable {
    var id = UUID()
    var feature: String
    var cols: Int = 2   // 1...4
    var rows: Int = 1   // 1...3
}

/// The features the + menu offers. v1 ships iPod Mode; more slot in here.
enum CreateFeature: String, CaseIterable, Identifiable {
    case ipod = "iPod Mode"
    var id: String { rawValue }
    var icon: String { switch self { case .ipod: "opticaldisc" } }
}

/// The Create tab: a 4-column grid of resizable glass-pill widgets. The + menu (top right) adds a
/// feature; drag a tile's bottom-right handle to resize; hold to remove. Layout persists.
struct CreatePage: View {
    @EnvironmentObject var coordinator: Coordinator
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.createTiles) private var tilesJSON = ""
    @State private var tiles: [CreateTile] = []
    @State private var showIPod = false

    private let gap: CGFloat = 12
    private let pad: CGFloat = 16
    private let unit: CGFloat = 96

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let colW = (geo.size.width - pad * 2 - gap * 3) / 4
                ScrollView {
                    if tiles.isEmpty {
                        ContentUnavailableView(
                            "Nothing added", systemImage: "square.grid.2x2",
                            description: Text("Tap + to add a widget. Drag its corner to resize, hold to remove."))
                            .padding(.top, 60)
                    } else {
                        VStack(alignment: .leading, spacing: gap) {
                            ForEach(Array(rows().enumerated()), id: \.offset) { _, row in
                                HStack(spacing: gap) {
                                    ForEach(row) { tile in tileView(tile, colW: colW) }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(pad)
                    }
                }
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(CreateFeature.allCases) { f in
                            Button { add(f) } label: { Label(f.rawValue, systemImage: f.icon) }
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .fullScreenCover(isPresented: $showIPod) { IPodView(player: coordinator.player) }
        }
        // Opened by a right-swipe from Home; a left-swipe closes it.
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -90, abs(v.translation.height) < 60 { dismiss() }
        })
        .onAppear { tiles = decode() }
    }

    // MARK: layout

    /// Greedy row packing: tiles fill left-to-right, wrapping when a row's columns exceed 4.
    private func rows() -> [[CreateTile]] {
        var out: [[CreateTile]] = []
        var row: [CreateTile] = []
        var used = 0
        for t in tiles {
            let c = min(max(t.cols, 1), 4)
            if used + c > 4 { out.append(row); row = []; used = 0 }
            row.append(t); used += c
        }
        if !row.isEmpty { out.append(row) }
        return out
    }

    private func width(_ tile: CreateTile, colW: CGFloat) -> CGFloat {
        let c = CGFloat(min(max(tile.cols, 1), 4))
        return colW * c + gap * (c - 1)
    }

    @ViewBuilder private func tileView(_ tile: CreateTile, colW: CGFloat) -> some View {
        let feature = CreateFeature(rawValue: tile.feature)
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                Image(systemName: feature?.icon ?? "questionmark").font(.title)
                Text(feature?.rawValue ?? tile.feature).font(.footnote.weight(.semibold))
            }
            .frame(width: width(tile, colW: colW), height: unit * CGFloat(tile.rows))
            .glassEffect(.regular, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { if feature == .ipod { showIPod = true } }
            .contextMenu {
                Button(role: .destructive) { remove(tile) } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
            ResizeHandle(colStep: colW + gap, rowStep: unit) { dCols, dRows in
                resize(tile, dCols: dCols, dRows: dRows)
            }
            .padding(6)
        }
    }

    // MARK: mutations

    private func add(_ f: CreateFeature) { tiles.append(CreateTile(feature: f.rawValue)); persist() }
    private func remove(_ tile: CreateTile) { tiles.removeAll { $0.id == tile.id }; persist() }

    private func resize(_ tile: CreateTile, dCols: Int, dRows: Int) {
        guard let i = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        tiles[i].cols = min(max(tiles[i].cols + dCols, 1), 4)
        tiles[i].rows = min(max(tiles[i].rows + dRows, 1), 3)
        persist()
    }

    // MARK: persistence

    private func decode() -> [CreateTile] {
        (try? JSONDecoder().decode([CreateTile].self, from: Data(tilesJSON.utf8))) ?? []
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(tiles) {
            tilesJSON = String(decoding: data, as: UTF8.self)
        }
    }
}

/// Bottom-right drag handle: translation snaps to whole grid steps and commits on release.
/// ponytail: commit-on-release only, no live preview — add one if resizing feels blind.
struct ResizeHandle: View {
    let colStep: CGFloat
    let rowStep: CGFloat
    let onCommit: (Int, Int) -> Void

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(.ultraThinMaterial, in: Circle())
            .gesture(DragGesture()
                .onEnded { v in
                    onCommit(Int((v.translation.width / colStep).rounded()),
                             Int((v.translation.height / rowStep).rounded()))
                })
    }
}
