//
//  VideoFrameExtractor.swift
//  SnapBack
//
//  Created by Bryan Kahl on 11/1/26.
//

import AVFoundation
import CoreGraphics
import UIKit

/// Pure video-frame extraction for dedup. No policy lives here: this file
/// only turns a video into a still frame image. A nil frame means
/// "couldn't read the video" — callers must treat that as "don't skip,
/// import it", never as a match.
enum VideoFrameExtractor {
    /// The middle frame of the video (50% of duration). Mid-video avoids
    /// black fade-in frames at time zero, which would make every video
    /// look identical. Uses the preferred track transform so the frame
    /// has the same orientation on both sides (library + import).
    static func middleFrame(of asset: AVAsset) async -> UIImage? {
        let duration = asset.duration
        guard duration.seconds > 0, duration.seconds.isFinite else { return nil }
        let midpoint = CMTime(seconds: duration.seconds * 0.5, preferredTimescale: duration.timescale)
        return await frame(of: asset, at: midpoint)
    }

    static func middleFrame(of url: URL) async -> UIImage? {
        await middleFrame(of: AVAsset(url: url))
    }

    private static func frame(of asset: AVAsset, at time: CMTime) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                // Keep the generator alive until its handler fires.
                _ = generator
                if let cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
