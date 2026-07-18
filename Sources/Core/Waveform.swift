import AVFoundation

/// Decodes an audio file into a small set of RMS buckets for the lyrics-screen scrubber.
/// AVFoundation-decodable local files only (mp3/aac/m4a/alac/flac/wav/aiff): VLC exposes no
/// decoded samples, so its exclusive codecs (ogg/opus/ape/…) and remote streams return nil and
/// the scrubber falls back to ticks.
enum Waveform {
    /// ~`buckets` values normalized to 0...1, or nil when the asset can't be read.
    static func load(url: URL, buckets: Int = 120) async -> [Float]? {
        guard url.isFileURL else { return nil }
        return await Task.detached(priority: .utility) {
            decode(url: url, buckets: buckets)
        }.value
    }

    private static func decode(url: URL, buckets: Int) -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = (try? asset.tracks(withMediaType: .audio))?.first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return nil }

        // RMS per fixed-size block first (bounded memory), rebucketed to `buckets` after.
        var blocks: [Float] = []
        let blockSize = 4096
        var acc: Double = 0
        var accCount = 0
        while let sb = output.copyNextSampleBuffer() {
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0
            var ptr: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length, dataPointerOut: &ptr) == noErr,
                  let base = ptr else { continue }
            base.withMemoryRebound(to: Int16.self, capacity: length / 2) { samples in
                for i in 0 ..< length / 2 {
                    let v = Double(samples[i]) / 32768
                    acc += v * v
                    accCount += 1
                    if accCount == blockSize {
                        blocks.append(Float((acc / Double(blockSize)).squareRoot()))
                        acc = 0; accCount = 0
                    }
                }
            }
        }
        if accCount > 0 { blocks.append(Float((acc / Double(accCount)).squareRoot())) }
        guard blocks.count > 1 else { return nil }

        // Rebucket by max — peaks read better than averages at this resolution.
        var out = [Float](repeating: 0, count: buckets)
        for (i, v) in blocks.enumerated() {
            let b = min(i * buckets / blocks.count, buckets - 1)
            out[b] = max(out[b], v)
        }
        let peak = out.max() ?? 1
        guard peak > 0 else { return nil }
        return out.map { $0 / peak }
    }
}
