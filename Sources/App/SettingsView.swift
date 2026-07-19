import SwiftUI

/// Preference keys, shared between the Settings UI (@AppStorage) and the core classes that read
/// them straight from UserDefaults (NowPlaying, Player). One module, so both sides reference
/// these constants — no string drift.
enum Pref {
    static let theme = "appearance.theme"
    static let waveInMini = "miniPlayer.waveScrubber"
    static let lyricsInArtwork = "lyrics.inArtwork"
    static let carPlayTextFallback = "lyrics.carPlayTextFallback"
    static let sponsorBlock = "playback.sponsorBlock"

    /// Defaults that aren't false/empty. Call once at launch before anything reads them.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [sponsorBlock: true])
    }

    /// Accent themes. White is the house monotone default; the rest are user-picked exceptions
    /// to the no-colored-chrome rule, sanctioned via this Settings page (2026-07-19).
    static let themes: [(name: String, color: Color)] = [
        ("White", .white), ("Red", .red), ("Orange", .orange), ("Yellow", .yellow),
        ("Green", .green), ("Blue", .blue), ("Purple", .purple), ("Pink", .pink),
    ]

    static func color(for name: String) -> Color {
        themes.first { $0.name == name }?.color ?? .white
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
    @AppStorage(Pref.theme) private var theme = "White"
    @AppStorage(Pref.waveInMini) private var waveInMini = false
    @AppStorage(Pref.lyricsInArtwork) private var lyricsInArtwork = false
    @AppStorage(Pref.carPlayTextFallback) private var carPlayFallback = false
    @AppStorage(Pref.sponsorBlock) private var sponsorBlock = true
    @State private var cachesCleared = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Accent Colour", selection: $theme) {
                        ForEach(Pref.themes, id: \.name) { t in
                            Label {
                                Text(t.name)
                            } icon: {
                                Circle().fill(t.color).frame(width: 18, height: 18)
                            }
                            .tag(t.name)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Tints buttons and controls everywhere. White is the stock look.")
                }

                Section {
                    Toggle("Waveform Scrubber", isOn: $waveInMini)
                } header: {
                    Text("Mini Player")
                } footer: {
                    Text("Draws the playing track's waveform in the dock pill, drag to seek. Local files only — streams and VLC-only codecs show ticks.")
                }

                Section {
                    Toggle("Lyrics on Artwork", isOn: $lyricsInArtwork)
                    Toggle("CarPlay Text Fallback", isOn: $carPlayFallback)
                } header: {
                    Text("Lyrics")
                } footer: {
                    Text("Lyrics on Artwork renders the current line into the Lock Screen and CarPlay cover. Text Fallback pushes the line into the artist field instead, for head units that cache artwork.")
                }

                Section {
                    Toggle("SponsorBlock", isOn: $sponsorBlock)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Skips community-flagged sponsor segments in YouTube streams.")
                }

                Section {
                    Button(cachesCleared ? "Caches Cleared" : "Clear Caches") { clearCaches() }
                        .disabled(cachesCleared)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Drops cached lyrics, artwork thumbnails and waveforms — including remembered \"nothing found\" results, so every track retries lookup on its next play.")
                }
            }
            .navigationTitle("Settings")
        }
        // Sheets don't inherit the shell's chrome — restate it, live-tinted by the picker.
        .tint(Pref.color(for: theme))
        .preferredColorScheme(.dark)
    }

    private func clearCaches() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for sub in ["lyrics", "artwork", "waveform"] {
            try? FileManager.default.removeItem(at: caches.appendingPathComponent(sub))
        }
        cachesCleared = true
    }
}
