import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var showingImporter = false
    @State private var youtubeText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Paste a YouTube link", text: $youtubeText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") {
                            if let url = URL(string: youtubeText), url.host != nil {
                                library.add(youtubeURL: url)
                                youtubeText = ""
                            }
                        }
                        .disabled(youtubeText.isEmpty)
                    }
                }

                Section {
                    ForEach(library.items) { item in
                        Button {
                            coordinator.play(item, in: library.items)
                        } label: {
                            HStack {
                                Image(systemName: item.isVideo ? "film" : "music.note")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text(item.title).lineLimit(1)
                                    if !item.artist.isEmpty {
                                        Text(item.artist).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete { library.remove(at: $0) }
                }
            }
            .navigationTitle("Roadie")
            .toolbar {
                Button { showingImporter = true } label: { Image(systemName: "plus") }
            }
            .overlay {
                if library.items.isEmpty {
                    ContentUnavailableView("Nothing here yet",
                                           systemImage: "music.note.list",
                                           description: Text("Import files with + or paste a YouTube link."))
                }
                if coordinator.busy { ProgressView().controlSize(.large) }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.audio, .movie, .data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    // .lrc files attach as lyrics rather than becoming tracks.
                    let (lrc, media) = urls.partitioned { $0.pathExtension.lowercased() == "lrc" }
                    library.add(pickedURLs: media)
                    for url in lrc { attachLRC(url) }
                }
            }
            .alert("Playback failed", isPresented: .init(
                get: { coordinator.lastError != nil },
                set: { if !$0 { coordinator.lastError = nil } })
            ) { Button("OK", role: .cancel) {} } message: {
                Text(coordinator.lastError ?? "")
            }
            .sheet(isPresented: $coordinator.showPlayer) {
                PlayerView()
            }
        }
    }

    /// Attach a dropped .lrc to the library item whose basename matches (SPEC §3).
    private func attachLRC(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        if let match = library.items.first(where: {
            $0.title.lowercased() == base || "\($0.artist) - \($0.title)".lowercased() == base
        }) {
            LyricsResolver.attach(lrcText: text, cacheKey: match.id.uuidString)
        }
    }
}

private extension Array {
    func partitioned(by belongsInFirst: (Element) -> Bool) -> ([Element], [Element]) {
        var a: [Element] = [], b: [Element] = []
        for e in self { belongsInFirst(e) ? a.append(e) : b.append(e) }
        return (a, b)
    }
}
