//
//  ImageFingerprinter.swift
//  SnapBack
//
//  Created by Bryan Kahl on 11/1/26.
//

import CoreGraphics
import UIKit
import Vision

/// Pure image fingerprinting for dedup. No policy lives here: this file only
/// turns an image into a Vision feature print and measures distance between
/// prints. A nil print (or nil distance) means "couldn't read/compare the
/// image" — callers must treat that as "don't skip, import it", never as
/// a match.
///
/// Why Vision instead of dHash: dHash compares raw pixel brightness, so
/// re-encodes (PhotoKit storage, thumbnail decode) flip bits on detailed
/// images and push true matches past the threshold — the "random unedited
/// duplicates" failure. Vision feature prints describe what the image shows,
/// so the same photo re-encoded, thumbnailed, or mildly edited lands on
/// nearly the same print.
enum ImageFingerprinter {
    /// Vision feature print for the image. Synchronous Vision work (a few
    /// milliseconds per image); callers run it inside async import work, and
    /// the loop yields between items so the UI stays responsive.
    /// Returns nil if the image can't be read or the request fails.
    static func fingerprint(_ image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        return fingerprint(cgImage)
    }

    static func fingerprint(_ cgImage: CGImage) -> VNFeaturePrintObservation? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    /// Float distance between two feature prints. Smaller = more similar.
    /// 0 = identical. Nil = couldn't compare (treat as no match, never skip).
    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        do {
            try a.computeDistance(&d, to: b)
            return d
        } catch {
            return nil
        }
    }
}
