//
//  LibraryScanner.swift
//  SnapBack
//
//  Created by Bryan Kahl on 11/1/26.
//

import AVFoundation
import Photos
import UIKit

/// The dedup index for one import run: fingerprints of existing Library
/// assets. An empty index means "don't skip anything" (no access, or
/// nothing found), so dedup always fails open to importing.
struct LibraryFingerprintIndex {
    private let hashes: [UInt64]

    init(hashes: [UInt64]) {
        self.hashes = hashes
    }

    static let empty = LibraryFingerprintIndex(hashes: [])

    func hasCloseMatch(_ hash: UInt64, threshold: Int) -> Bool {
        hashes.contains { ImageFingerprinter.distance($0, hash) <= threshold }
    }
}

/// Photo and video indexes kept SEPARATE on purpose: a photo and a video
/// of the same moment look alike, but they are distinct memories. Mixing
/// them would let a video get skipped because a photo of the same scene
/// is already in the library (or vice versa).
struct LibraryDedupIndex {
    let photos: LibraryFingerprintIndex
    let videos: LibraryFingerprintIndex
}

enum LibraryScanner {
    /// Builds the photo index over the WHOLE library (no date filter).
    /// A date filter would miss manual saves made days later — the exact
    /// case dedup must catch on a reinstall. If read access isn't available,
    /// returns an empty index (import as today).
    static func buildIndex() async -> LibraryFingerprintIndex {
        guard await ensureReadAccess() else { return .empty }
        let assets = PHAsset.fetchAssets(with: .image, options: nil)
        var photoAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in photoAssets.append(asset) }
        var hashes: [UInt64] = []
        for asset in photoAssets {
            guard let image = await thumbnail(for: asset),
                  let hash = ImageFingerprinter.fingerprint(image) else { continue }
            hashes.append(hash)
        }
        return LibraryFingerprintIndex(hashes: hashes)
    }

    /// Builds the video index over the WHOLE library (no date filter, same
    /// reason as photos). One middle-frame fingerprint per video. If read
    /// access isn't available, returns an empty index (import as today).
    static func buildVideoIndex() async -> LibraryFingerprintIndex {
        guard await ensureReadAccess() else { return .empty }
        let assets = PHAsset.fetchAssets(with: .video, options: nil)
        var videoAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in videoAssets.append(asset) }
        var hashes: [UInt64] = []
        for asset in videoAssets {
            guard let avAsset = await requestAVAsset(for: asset),
                  let frame = await VideoFrameExtractor.middleFrame(of: avAsset),
                  let hash = ImageFingerprinter.fingerprint(frame) else { continue }
            hashes.append(hash)
        }
        return LibraryFingerprintIndex(hashes: hashes)
    }

    private static func ensureReadAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await requestReadAccess()
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    private static func requestReadAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func thumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 256, height: 256),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            _ = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }
}
