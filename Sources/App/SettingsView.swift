import SwiftUI

/// Preference keys, shared between the Settings UI (@AppStorage) and the core classes that read
/// them straight from UserDefaults (NowPlaying, Player). One module, so both sides reference
/// these constants — no string drift.
enum Pref {
    static let theme = "appearance.theme"
    static let waveInMini = "miniPlayer.waveScrubber"
    static let carPlayTextFallback = "lyrics.carPlayTextFallback"
    static let sponsorBlock = "playback.sponsorBlock"

    /// Defaults that aren't false/empty. Call once at launch before anything reads them.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [sponsorBlock: true])
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
    @AppStorage(Pref.waveInMini) private var waveInMini = false
    @AppStorage(Pref.carPlayTextFallback) private var carPlayFallback = false
    @AppStorage(Pref.sponsorBlock) private var sponsorBlock = true
    @State private var cachesCleared = false
    // Owned by the system, not UserDefaults — read back what's actually set.
    @State private var appIcon: String? = UIApplication.shared.alternateIconName

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ColorPicker("Accent Colour", selection: Binding(
                        get: { Pref.color(for: theme) },
                        set: { theme = Pref.hex(of: $0) }
                    ), supportsOpacity: false)
                    if !theme.isEmpty {
                        Button("Reset to White") { theme = "" }
                    }
                    NavigationLink {
                        IconPickerView(appIcon: $appIcon)
                    } label: {
                        LabeledContent("App Icon",
                                       value: IconPickerView.icons.first { $0.id == appIcon }?.label ?? "Verse")
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Tints buttons and controls everywhere — any colour. White is the stock look.")
                }

                Section {
                    Toggle("Waveform Scrubber", isOn: $waveInMini)
                } header: {
                    Text("Mini Player")
                } footer: {
                    Text("Draws the playing track's waveform in the dock pill, drag to seek. Local files only — streams and VLC-only codecs show ticks.")
                }

                Section {
                    Toggle("CarPlay Lyrics", isOn: $carPlayFallback)
                } header: {
                    Text("Lyrics")
                } footer: {
                    Text("Shows the current lyric line in the artist field on CarPlay and the Lock Screen. Off, the artist shows normally; per-line lyrics still run in the Live Activity.")
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

/// Icon gallery: each choice shown as the actual icon, tap to apply. `id` is the alternate
/// icon name handed to setAlternateIconName (nil = the primary).
struct IconPickerView: View {
    @Binding var appIcon: String?

    static let icons: [(id: String?, label: String, preview: String)] = [
        (nil, "Verse", "IconPreview-Verse"),
        ("AppIcon-Yeezus", "Yeezus", "IconPreview-Yeezus"),
        ("AppIcon-Yandhi", "Yandhi", "IconPreview-Yandhi"),
        ("AppIcon-Classic", "Classic", "IconPreview-Classic"),
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
