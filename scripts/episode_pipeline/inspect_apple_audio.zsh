#!/bin/zsh
set -euo pipefail
[[ $# == 1 ]] || { print -u2 'Usage: inspect_apple_audio.zsh /absolute/audio.opus'; exit 1; }
# Read-only AVFoundation inspection. The player is never started or made audible.
/usr/bin/swift - "$1" <<'SWIFT'
import Foundation
import AVFoundation
let mediaURL = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: mediaURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
Task {
    do {
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard playable && !tracks.isEmpty else {
            throw NSError(domain: "MediaInspection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio is not playable."])
        }
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        for _ in 0..<100 {
            if item.status != .unknown { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard item.status == .readyToPlay else {
            throw item.error ?? NSError(domain: "MediaInspection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Player did not become ready."])
        }
        var seeks: [[String: Any]] = []
        let total = CMTimeGetSeconds(duration)
        guard total.isFinite && total > 1 else {
            throw NSError(domain: "MediaInspection", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid audio duration."])
        }
        let middle = total / 2
        for seconds in [0.0, min(30, total-1), middle, min(middle+30, total-1), min(middle+15, total-1), total-1, 0.0] {
            let target = CMTime(seconds: seconds, preferredTimescale: 48000)
            let completed = await withCheckedContinuation { continuation in
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) {
                    continuation.resume(returning: $0)
                }
            }
            let actual = CMTimeGetSeconds(player.currentTime())
            guard completed && actual.isFinite && abs(actual - seconds) <= 0.05 else {
                throw NSError(domain: "MediaInspection", code: 3, userInfo: [NSLocalizedDescriptionKey: "Seek did not reach requested time."])
            }
            seeks.append(["requested_s": seconds, "actual_s": actual, "completed": completed])
        }
        player.replaceCurrentItem(with: nil)
        let result: [String: Any] = ["file": mediaURL.lastPathComponent,
            "playable": playable, "duration_s": CMTimeGetSeconds(duration),
            "audio_tracks": tracks.count, "paused_native_seeks": seeks,
            "audible_playback_checked": false, "ios_checked": false]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    } catch {
        fputs("AVFoundation inspection failed: \(error)\n", stderr)
        exit(1)
    }
}
RunLoop.main.run()
SWIFT
