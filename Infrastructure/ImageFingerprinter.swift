//
//  ImageFingerprinter.swift
//  SnapBack
//
//  Created by Bryan Kahl on 11/1/26.
//

import UIKit
import CoreGraphics

/// Pure image fingerprinting for dedup. No policy lives here: this file only
/// turns an image into a 64-bit dHash and measures distance between hashes.
/// A nil fingerprint means "couldn't read the image" — callers must treat
/// that as "don't skip, import it", never as a match.
enum ImageFingerprinter {
    /// dHash: center-crop to square, shrink to 9x8 grayscale, compare each
    /// pixel to its right neighbor. The square crop matters: the library
    /// scanner fetches aspectFill square thumbnails, so the import side must
    /// hash the same cropped geometry or nothing matches.
    /// Same picture re-encoded (different JPEG, different size) lands on the
    /// same or nearly the same hash. Returns nil if the image can't be read.
    static func fingerprint(_ image: UIImage) -> UInt64? {
        guard let cgImage = image.cgImage else { return nil }
        return fingerprint(cgImage)
    }

    static func fingerprint(_ cgImage: CGImage) -> UInt64? {
        let side = min(cgImage.width, cgImage.height)
        let x = (cgImage.width - side) / 2
        let y = (cgImage.height - side) / 2
        guard let square = cgImage.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else { return nil }
        let width = 9
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let left = pixels[y * width + x]
                let right = pixels[y * width + x + 1]
                if left > right {
                    hash |= (UInt64(1) << (y * (width - 1) + x))
                }
            }
        }
        return hash
    }

    /// Number of differing bits. 0 = identical fingerprint.
    /// Small (single digits) = same picture re-encoded. Large = different picture.
    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
