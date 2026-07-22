import SwiftUI

/// A user-added widget on the Create canvas: a feature, sized in a 4-column grid.
struct CreateTile: Codable, Identifiable, Hashable {
    var id = UUID()
    var feature: String
    var cols: Int = 1   // 1...4 — starts a 1x1 square, widen to make a pill
    var rows: Int = 1   // 1...3
}

/// The features the + menu offers. v1 ships iPod Mode; more slot in here.
enum CreateFeature: String, CaseIterable, Identifiable {
    case ipod = "iPod Mode"
    var id: String { rawValue }
    var icon: String { switch self { case .ipod: "opticaldisc" } }
}

/// The Deck: a 4-column grid of resizable glass-pill widgets (renamed from "Create", #7). The +
/// menu (top right) adds a feature; hold a tile to enter edit mode, then drag the right-edge
/// bumper to resize or tap the minus to remove. Layout persists.
struct CreatePage: View {
    @EnvironmentObject var coordinator: Coordinator
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.createTiles) private var tilesJSON = ""
    @State private var tiles: [CreateTile] = []
    @State private var showIPod = false
    @State private var showAdd = false
    @State private var editing = false      // #8: resize/remove only in edit mode

    private let gap: CGFloat = 12
    private let pad: CGFloat = 16

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let colW = (geo.size.width - pad * 2 - gap * 3) / 4
                ScrollView {
                    if tiles.isEmpty {
                        ContentUnavailableView(
                            "Nothing added", systemImage: "square.grid.2x2",
                            description: Text("Tap + to add a widget. Hold a tile to edit — drag its edge bumper to resize, tap minus to remove."))
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
            .navigationTitle("Deck")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if editing {
                        Button("Done") { withAnimation(.snappy) { editing = false } }
                    } else {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddWidgetSheet { add($0); showAdd = false }
                    .presentationDetents([.medium, .large])
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

    /// A cell is `colW` square, so a 1x1 tile is a square and widening it makes a pill.
    private func size(_ tile: CreateTile, colW: CGFloat) -> CGSize {
        let c = CGFloat(min(max(tile.cols, 1), 4)), r = CGFloat(min(max(tile.rows, 1), 3))
        return CGSize(width: colW * c + gap * (c - 1), height: colW * r + gap * (r - 1))
    }

    @ViewBuilder private func tileView(_ tile: CreateTile, colW: CGFloat) -> some View {
        let feature = CreateFeature(rawValue: tile.feature)
        let sz = size(tile, colW: colW)
        // #8: at 1x1 the tile is just its icon; widen/tall and the name text appears.
        let iconOnly = tile.cols == 1 && tile.rows == 1
        WidgetBubble(title: feature?.rawValue ?? tile.feature,
                     icon: feature?.icon, iconOnly: iconOnly, size: sz)
            // Tap launches the feature only when not editing; hold enters edit mode (#8).
            .onTapGesture {
                guard !editing else { return }
                if feature == .ipod { showIPod = true }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                withAnimation(.snappy) { editing = true }
            }
            .overlay(alignment: .topLeading) {
                if editing {
                    Button { remove(tile) } label: {
                        Image(systemName: "minus")
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
            .overlay(alignment: .trailing) {
                if editing {
                    ResizeBumper(colStep: colW + gap, rowStep: colW + gap) { dCols, dRows in
                        resize(tile, dCols: dCols, dRows: dRows)
                    }
                    .padding(.trailing, 4)
                }
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

/// The widget itself: a glass bubble with a rounded edge and its name — no icon. A 1x1 tile is a
/// rounded square; widen it and the corner radius grows to a pill (Control-Center-style shapes).
struct WidgetBubble: View {
    let title: String
    var icon: String? = nil
    var iconOnly: Bool = false      // 1x1 tile → glyph instead of the name (#8)
    let size: CGSize

    var body: some View {
        let radius = size.width > size.height * 1.4
            ? size.height / 2                              // wide → pill
            : min(size.width, size.height) * 0.28          // square-ish → rounded square
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if iconOnly, let icon {
                Image(systemName: icon)
                    .font(.title2).foregroundStyle(.white)
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(10)
        .frame(width: size.width, height: size.height)
        .glassEffect(.regular, in: shape)
        .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 1) }
    }
}

/// The + palette: previews of each widget as it will look, tap (or drag) one onto the canvas.
/// ponytail: tap-to-add — a modal sheet can't be a drop target for the canvas beneath it, so the
/// literal drag-from-sheet isn't possible; the preview + tap is the honest version.
struct AddWidgetSheet: View {
    let onPick: (CreateFeature) -> Void
    @Environment(\.dismiss) private var dismiss

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 16) {
                    ForEach(CreateFeature.allCases) { f in
                        Button { onPick(f) } label: {
                            // Square glass bubble — the same format the tile takes on the canvas.
                            WidgetBubble(title: f.rawValue, size: CGSize(width: 150, height: 150))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Right-edge resize bumper: a glass capsule grip (#9, replaces the corner arrow icon). Drag
/// snaps to whole grid steps and commits on release.
/// ponytail: commit-on-release only, no live preview — add one if resizing feels blind.
struct ResizeBumper: View {
    let colStep: CGFloat
    let rowStep: CGFloat
    let onCommit: (Int, Int) -> Void

    var body: some View {
        Color.clear
            .frame(width: 11, height: 40)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1) }
            .contentShape(Rectangle().inset(by: -10))
            .gesture(DragGesture()
                .onEnded { v in
                    onCommit(Int((v.translation.width / colStep).rounded()),
                             Int((v.translation.height / rowStep).rounded()))
                })
    }
}
