import SwiftUI
import UniformTypeIdentifiers

/// Preference keys, shared between the Settings UI (@AppStorage) and the core classes that read
/// them straight from UserDefaults (NowPlaying, Player). One module, so both sides reference
/// these constants — no string drift.
enum Pref {
    static let theme = "appearance.theme"
    static let carPlayTextFallback = "lyrics.carPlayTextFallback"
    static let lyricsCoverColour = "lyrics.coverColour"
    static let sponsorBlock = "playback.sponsorBlock"
    static let showFilePaths = "library.showFilePaths"
    static let tintedBackground = "appearance.tintedBackground"  // player bg from cover colour
    static let iPodMode = "appearance.iPodMode"                  // click-wheel skeleton (beta)
    static let createUnlocked = "create.unlocked"               // hidden Create page revealed
    static let createTiles = "create.tiles"                     // JSON [CreateTile]
    static let ipodWheelColour = "ipod.wheelColour"             // RRGGBB, "" = classic grey
    static let ipodScreenColour = "ipod.screenColour"           // RRGGBB, "" = classic green LCD
    static let lyricsFont = "lyrics.fontDesign"      // design keyword or PostScript name
    static let lyricsSize = "lyrics.fontSize"        // Double, points; 22 = old title2 look
    static let customSwatches = "appearance.customSwatches"  // comma-joined RRGGBB list

    // Home shelves: ordered, enabled-only ids (hold a shelf header to move/remove; the
    // ellipsis menu adds). Replaces the old per-shelf bools.
    static let homeSections = "home.sections"
    static let homeShelfSizes = "home.shelfSizes"   // "now:large,albums:small" — medium default

    /// Lyrics fonts, every one with a real name and previewable. `id` is a system design
    /// keyword or a PostScript name (iOS built-ins — nothing bundled).
    static let lyricFonts: [(id: String, name: String)] = [
        ("system", "San Francisco"), ("rounded", "SF Rounded"), ("serif", "New York"),
        ("mono", "SF Mono"), ("Charter-Roman", "Charter"), ("Georgia", "Georgia"),
        ("AvenirNext-Medium", "Avenir Next"), ("Palatino-Roman", "Palatino"),
        ("Baskerville", "Baskerville"), ("Futura-Medium", "Futura"),
        ("Menlo-Regular", "Menlo"), ("TimesNewRomanPS-BoldMT", "Times New Roman"),
    ]

    static func lyricsFont(id: String, size: Double) -> Font {
        switch id {
        case "system": .system(size: size, weight: .bold)
        case "rounded": .system(size: size, weight: .bold, design: .rounded)
        case "serif": .system(size: size, weight: .bold, design: .serif)
        case "mono": .system(size: size, weight: .bold, design: .monospaced)
        default: .custom(id, size: size)
        }
    }
    static let onlineMetadata = "metadata.online"
    static let metadataExcludedFolders = "metadata.excludedFolders"  // newline-joined root names

    /// Accent swatches offered before the custom picker (inbox-3: "a group like the icon
    /// selection, and the colour of the square"). "" = stock white; Red = the Yeezus/Classic
    /// tape, Violet = the exact Yandhi tape square. The rest are pastels (2026-07-21 request).
    static let accentPresets: [(hex: String, name: String)] = [
        ("", "White"), ("F0241C", "Red"), ("97479E", "Violet"),
        ("AEC6CF", "Blue"), ("77DD77", "Green"), ("FFB347", "Orange"), ("FFB6C1", "Pink"),
    ]

    /// Defaults that aren't false/empty. Call once at launch before anything reads them.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            sponsorBlock: true, lyricsSize: 22.0,
            homeSections: "now,playlists,albums,tracks",
        ])
    }

    /// Accent stored as RRGGBB hex; anything unparseable (including the old preset names and
    /// the empty default) means stock white. Full colour range, user-picked exception to the
    /// no-colored-chrome rule, sanctioned via this Settings page (2026-07-19).
    static func color(for stored: String) -> Color {
        guard stored.count == 6, let v = UInt32(stored, radix: 16) else { return .white }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    static func hex(of color: Color) -> String {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

extension View {
    /// Sheets don't inherit the shell's tint — restate the user's accent on presentation.
    /// ponytail: reads defaults once at render; a theme change mid-sheet lags until reopen.
    func themedTint() -> some View {
        tint(Pref.color(for: UserDefaults.standard.string(forKey: Pref.theme) ?? "White"))
    }
}

/// The personalization hub (inbox-3): every user-tweakable knob lives here, grouped by surface.
struct SettingsView: View {
    @AppStorage(Pref.theme) private var theme = ""
    @AppStorage(Pref.carPlayTextFallback) private var carPlayFallback = false
    @AppStorage(Pref.lyricsCoverColour) private var lyricsCoverColour = false
    @AppStorage(Pref.sponsorBlock) private var sponsorBlock = true
    @AppStorage(Pref.lyricsFont) private var lyricsFont = "system"
    @AppStorage(Pref.lyricsSize) private var lyricsSize = 22.0
    @AppStorage(Pref.customSwatches) private var customSwatches = ""
    @AppStorage(Pref.tintedBackground) private var tintedBackground = false
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var cachesCleared = false
    @State private var wipAlert: String?

    /// Planned features (mirrors BACKLOG.md) — shown faded under "In the Works", grouped by the
    /// surface they'll land on so the list reads by where it'll appear (2026-07-21 user request).
    /// (iPod Mode graduated to a beta toggle in Appearance.)
    static let inTheWorks: [(area: String, items: [String])] = [
        ("Player", ["Stem Player (per-stem audio)", "Karaoke Word Timing"]),
        ("Library", ["Jellyfin Servers", "Locations Tab", "Hi-Res / Low-Res Version Picker",
                     "Folder Organize Macro"]),
        ("Home", ["Wrapped (year recap)"]),
        ("Import", ["Import Summary Sheet"]),
    ]
    // Owned by the system, not UserDefaults — read back what's actually set.
    @State private var appIcon: String? = UIApplication.shared.alternateIconName

    // Import moved here from the Library tab menu (2026-07-21): Settings is the one place
    // that opens folders and files now.
    enum ImportKind {
        case folder, files
        var types: [UTType] {
            switch self {
            case .folder: [.folder]
            case .files: [.audio, .movie, .mpeg4Movie, .mpeg4Audio, .mp3, .wav, .aiff]
            }
        }
    }

    /// true = pushed inside Library's stack (top-left gear); false = standalone.
    var embedded = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
        // Sheets don't inherit the shell's chrome — restate it, live-tinted by the picker.
        .tint(Pref.color(for: theme))
        .preferredColorScheme(.dark)
    }

    private var content: some View {
            List {
                // Library first — import and maintenance outrank cosmetics.
                Section {
                    // Import lives inside Locations now (its + menu, top right).
                    NavigationLink {
                        LocationsView()
                    } label: {
                        LabeledContent {
                            Text(library.importedRoots.isEmpty ? "None"
                                : "\(library.importedRoots.count)")
                        } label: {
                            Label("Locations", systemImage: "folder")
                        }
                    }
                    NavigationLink {
                        MetadataSettingsView()
                    } label: {
                        Label("Metadata & Fetching", systemImage: "text.magnifyingglass")
                    }
                } header: {
                    Text("Library")
                } footer: {
                    Text("Locations lists every imported folder (swipe to remove — files and their sidecars stay on disk, re-import restores everything). Fetching and online lookup live under Metadata & Fetching.")
                }

                Section {
                    AccentSwatches(theme: $theme, custom: $customSwatches)
                    ColorPicker("Custom Colour", selection: Binding(
                        get: { Pref.color(for: theme) },
                        set: { theme = Pref.hex(of: $0) }
                    ), supportsOpacity: false)
                    // Promote the picked colour into the swatch row for one-tap switching.
                    if !theme.isEmpty,
                       !Pref.accentPresets.contains(where: { $0.hex == theme.uppercased() }),
                       !customSwatches.split(separator: ",").map(String.init).contains(theme.uppercased()) {
                        Button("Save Colour as Preset") {
                            let all = customSwatches.split(separator: ",").map(String.init) + [theme.uppercased()]
                            customSwatches = all.suffix(6).joined(separator: ",")  // cap the row
                        }
                    }
                    NavigationLink {
                        LyricsFontPicker(selection: $lyricsFont)
                    } label: {
                        LabeledContent("Lyrics Font",
                                       value: Pref.lyricFonts.first { $0.id == lyricsFont }?.name ?? "San Francisco")
                    }
                    HStack {
                        Text("Lyrics Size")
                        Slider(value: $lyricsSize, in: 16...34, step: 1)
                        Text("\(Int(lyricsSize))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        IconPickerView(appIcon: $appIcon)
                    } label: {
                        LabeledContent("App Icon",
                                       value: IconPickerView.icons.first { $0.id == appIcon }?.label ?? "Verse")
                    }
                    NavigationLink { IPodSettingsView() } label: {
                        Label("iPod Mode", systemImage: "opticaldisc")
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Tints buttons and controls everywhere — any colour. White is the stock look.")
                }

                Section {
                    Toggle("CarPlay Lyrics", isOn: $carPlayFallback)
                    Toggle("Colour From Cover", isOn: $lyricsCoverColour)
                    Toggle("Tinted Background", isOn: $tintedBackground)
                } header: {
                    Text("Lyrics")
                } footer: {
                    Text("CarPlay Lyrics shows the current line in the artist field on CarPlay and the Lock Screen. Colour From Cover tints the active lyric line with the album cover's dominant colour instead of white.")
                }

                Section {
                    Toggle("SponsorBlock", isOn: $sponsorBlock)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("SponsorBlock skips community-flagged sponsor segments in YouTube streams. The sleep timer moved to the player's moon icon.")
                }

                Section {
                    Button(cachesCleared ? "Caches Cleared" : "Clear Caches") { clearCaches() }
                        .disabled(cachesCleared)
                    if let backup = library.backupURL() {
                        ShareLink(item: backup) { Text("Export Library Backup") }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Clear Caches drops cached lyrics, artwork and waveforms — including remembered \"nothing found\" results. Export Library Backup shares one JSON with the whole library, playlists and folders (covers YouTube items, which have no files to carry sidecars).")
                }

                // Faded skeletons for what's planned — tap says so. Mirrors BACKLOG.md.
                // One section per surface (Player / Library / Home / Import).
                ForEach(Self.inTheWorks, id: \.area) { group in
                    Section {
                        ForEach(group.items, id: \.self) { name in
                            Button { wipAlert = name } label: {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Text("planned").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.secondary.opacity(0.6))
                        }
                    } header: {
                        Text("In the Works · \(group.area)")
                    } footer: {
                        if group.area == Self.inTheWorks.last?.area {
                            Text("Planned features from the backlog — not built yet, grouped by where they'll show up.")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .alert(wipAlert ?? "", isPresented: .init(
                get: { wipAlert != nil }, set: { if !$0 { wipAlert = nil } })
            ) { Button("OK", role: .cancel) {} } message: {
                Text("Work in progress — it's on the backlog.")
            }
    }

    private func clearCaches() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for sub in ["lyrics", "artwork", "waveform"] {
            try? FileManager.default.removeItem(at: caches.appendingPathComponent(sub))
        }
        cachesCleared = true
    }
}

/// Everything about fetching + where metadata lives, moved off the main Settings list into one
/// place (2026-07-21 user request): the online toggle, per-folder opt-out, the Fetch buttons,
/// file-path visibility and the sidecar location.
struct MetadataSettingsView: View {
    @EnvironmentObject var library: LibraryStore
    @AppStorage(Pref.onlineMetadata) private var onlineMetadata = false
    @AppStorage(Pref.showFilePaths) private var showFilePaths = false
    @AppStorage(Pref.metadataExcludedFolders) private var excludedCSV = ""

    private var excluded: Set<String> {
        Set(excludedCSV.split(separator: "\n").map(String.init))
    }
    private func setExcluded(_ root: String, _ off: Bool) {
        var set = excluded
        if off { set.insert(root) } else { set.remove(root) }
        excludedCSV = set.sorted().joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                Toggle("Online Metadata", isOn: $onlineMetadata)
            } footer: {
                Text("Looks up album, artist and high-res cover art via MusicBrainz on import and rescan. The Fetch buttons below always go online regardless. Off by default — no network unless you ask.")
            }

            Section {
                busyButton("Rescan Library") { await library.rescanLibrary() }
                busyButton("Fetch Metadata") { await library.fetchOnlineTags() }
                busyButton("Fetch Artwork") { await library.fetchOnlineArtwork() }
                busyButton("Fetch Lyrics") { await library.fetchAllLyrics() }
                if library.rescanning, !library.rescanStatus.isEmpty {
                    Text(library.rescanStatus)
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                } else if !library.lastFetchSummary.isEmpty {
                    Text(library.lastFetchSummary)
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Fetch")
            } footer: {
                Text("Albums are looked up whole — one release match brings the tracklist (disc and track numbers) and a single cover for the folder. Lone tracks are searched individually. Covers and albums from MusicBrainz, lyrics from LRCLIB — all saved beside your files.")
            }

            if !library.importedRoots.isEmpty {
                Section {
                    ForEach(library.importedRoots, id: \.self) { root in
                        Toggle(root, isOn: Binding(
                            get: { !excluded.contains(root) },
                            set: { setExcluded(root, !$0) }))
                    }
                } header: {
                    Text("Search These Folders")
                } footer: {
                    Text("Turn a folder off to skip it during online lookups — for bootlegs, mixes or anything MusicBrainz won't have.")
                }
            }

            Section {
                Toggle("Show File Locations", isOn: $showFilePaths)
                NavigationLink {
                    SidecarLocationView()
                } label: {
                    LabeledContent("Metadata Location",
                                   value: library.customSidecarFolderName ?? "Beside files")
                }
            } header: {
                Text("Files")
            }
        }
        .navigationTitle("Metadata")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func busyButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack {
                Text(title)
                if library.rescanning { Spacer(); ProgressView() }
            }
        }
        .disabled(library.rescanning)
    }
}

/// Every imported folder on one page (was a row each in Settings), plus the import actions in a
/// top-right menu. Swipe to remove — files and sidecars stay on disk, so re-importing restores
/// the library.
struct LocationsView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var showingImport = false
    @State private var importKind: SettingsView.ImportKind = .files

    var body: some View {
        List {
            if library.importedRoots.isEmpty {
                ContentUnavailableView("No folders imported", systemImage: "folder",
                                       description: Text("Add music with the + button, top right."))
            } else {
                ForEach(library.importedRoots, id: \.self) { root in
                    LabeledContent("Folder", value: root)
                        .swipeActions {
                            Button(role: .destructive) {
                                library.removeImportedRoot(root)
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { importKind = .folder; showingImport = true } label: {
                        Label("Import Folder", systemImage: "folder.badge.plus")
                    }
                    Button { importKind = .files; showingImport = true } label: {
                        Label("Import Files", systemImage: "doc.badge.plus")
                    }
                } label: { Image(systemName: "plus") }
            }
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: importKind.types,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            switch importKind {
            case .folder: library.add(pickedURLs: urls)
            case .files: library.add(pickedFiles: urls)
            }
        }
    }
}

/// iPod Mode's own settings entry (was a bare toggle in Appearance): the enable switch plus the
/// click-wheel and screen colours, read by `IPodView`.
struct IPodSettingsView: View {
    @AppStorage(Pref.iPodMode) private var iPodMode = false
    @AppStorage(Pref.ipodWheelColour) private var wheelHex = ""
    @AppStorage(Pref.ipodScreenColour) private var screenHex = ""

    var body: some View {
        List {
            Section {
                Toggle("iPod Mode", isOn: $iPodMode)
            } footer: {
                Text("A classic click-wheel player over your library. Also available as a Create widget.")
            }
            Section {
                colorRow("Wheel", $wheelHex, defaultColour: Color(white: 0.85))
                colorRow("Screen", $screenHex, defaultColour: Color(red: 0.78, green: 0.85, blue: 0.78))
                if !wheelHex.isEmpty || !screenHex.isEmpty {
                    Button("Reset Colours") { wheelHex = ""; screenHex = "" }
                }
            } header: {
                Text("Colours")
            }
        }
        .navigationTitle("iPod Mode")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func colorRow(_ label: String, _ hex: Binding<String>, defaultColour: Color) -> some View {
        ColorPicker(label, selection: Binding(
            get: { hex.wrappedValue.isEmpty ? defaultColour : Pref.color(for: hex.wrappedValue) },
            set: { hex.wrappedValue = Pref.hex(of: $0) }
        ), supportsOpacity: false)
    }
}

/// Preset accent swatches (inbox-3): a tap-to-pick group like the icon gallery, the icon's
/// tape-square red among them. A custom colour outside the presets shows as an extra ringed dot.
private struct AccentSwatches: View {
    @Binding var theme: String
    @Binding var custom: String     // comma-joined saved custom hexes; hold one to remove it

    private let dot: CGFloat = 30

    private var customHexes: [String] { custom.split(separator: ",").map(String.init) }

    var body: some View {
        // Wraps if the user saves several custom presets; a plain HStack would clip.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Pref.accentPresets, id: \.hex) { preset in
                    swatch(hex: preset.hex, selected: theme.uppercased() == preset.hex)
                }
                ForEach(customHexes, id: \.self) { hex in
                    swatch(hex: hex, selected: theme.uppercased() == hex)
                        .contextMenu {
                            Button(role: .destructive) {
                                custom = customHexes.filter { $0 != hex }.joined(separator: ",")
                                if theme.uppercased() == hex { theme = "" }
                            } label: { Label("Remove Preset", systemImage: "trash") }
                        }
                }
                // A picked colour that isn't saved anywhere still shows its selection.
                if !theme.isEmpty,
                   !Pref.accentPresets.contains(where: { $0.hex == theme.uppercased() }),
                   !customHexes.contains(theme.uppercased()) {
                    swatch(hex: theme, selected: true)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 2)
        }

    }

    private func swatch(hex: String, selected: Bool) -> some View {
        Button { theme = hex } label: {
            Circle()
                .fill(Pref.color(for: hex))
                .frame(width: dot, height: dot)
                // White needs an outline to be visible on the dark row.
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: hex.isEmpty ? 1 : 0))
                .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2.5 : 0)
                    .padding(-4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Pref.accentPresets.first { $0.hex == hex }?.name ?? "Custom")
    }
}

/// Where sidecar metadata/lyrics get written: beside the music (default) or one folder the
/// user picks. Shows the active path so it's never a mystery.
struct SidecarLocationView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var picking = false

    var body: some View {
        List {
            Section {
                Button {
                    library.setCustomSidecarFolder(nil)
                } label: {
                    HStack {
                        Text("Beside the music files")
                        Spacer()
                        if library.customSidecarFolderName == nil {
                            Image(systemName: "checkmark").fontWeight(.semibold)
                        }
                    }
                }
                .tint(.primary)
                Button {
                    picking = true
                } label: {
                    HStack {
                        Text(library.customSidecarFolderName.map { "Folder: \($0)" } ?? "Choose a Folder…")
                        Spacer()
                        if library.customSidecarFolderName != nil {
                            Image(systemName: "checkmark").fontWeight(.semibold)
                        }
                    }
                }
                .tint(.primary)
            } footer: {
                Text("Tags (.verse.json) and lyrics (.lrc) save here. Beside the files keeps everything with your music (survives app wipes); a separate folder keeps your music folders untouched. Re-import reads both locations.")
            }
        }
        .navigationTitle("Metadata Location")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { library.setCustomSidecarFolder(url) }
        }
    }
}

/// Every font drawn in its own face — the row IS the preview.
struct LyricsFontPicker: View {
    @Binding var selection: String

    var body: some View {
        List(Pref.lyricFonts, id: \.id) { f in
            Button { selection = f.id } label: {
                HStack {
                    Text(f.name).font(Pref.lyricsFont(id: f.id, size: 20))
                    Spacer()
                    if selection == f.id { Image(systemName: "checkmark").fontWeight(.semibold) }
                }
            }
            .tint(.primary)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Lyrics Font")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Icon gallery: each choice shown as the actual icon, tap to apply. `id` is the alternate
/// icon name handed to setAlternateIconName (nil = the primary).
struct IconPickerView: View {
    @Binding var appIcon: String?

    static let icons: [(id: String?, label: String, preview: String)] = [
        (nil, "Verse", "IconPreview-Verse"),   // the classic green/violet disc, primary
        ("AppIcon-Yeezus", "Yeezus", "IconPreview-Yeezus"),
        ("AppIcon-Yandhi", "Yandhi", "IconPreview-Yandhi"),
    ]

    var body: some View {
        List(Self.icons, id: \.label) { icon in
            Button {
                appIcon = icon.id
                UIApplication.shared.setAlternateIconName(icon.id)
            } label: {
                HStack(spacing: 14) {
                    Image(icon.preview)
                        .resizable().scaledToFit()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 13.5))  // 60pt icon curvature
                    Text(icon.label)
                    Spacer()
                    if appIcon == icon.id {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                }
            }
            .tint(.primary)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}
