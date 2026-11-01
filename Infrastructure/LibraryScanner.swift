//
//  LibraryScanner.swift
//  SnapBack
//
//  Created by Bryan Kahl on 11/1/26.
//

import Photos
import UIKit

/// The dedup index for one import run: fingerprints of existing Library
/// PHOTOS near the import's dates. Photos only in v1 — videos import as today.
/// An empty index means "don't skip anything" (no access, or nothing nearby),
/// so dedup always fails open to importing.
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

enum LibraryScanner {
    /// Builds the index for the given memory dates. Metadata pre-filter first
    /// (creation date within windowDays, photos only), thumbnails only for
    /// candidates. Never blocks the UI: all Photos requests are async.
    /// If read access isn't available, returns an empty index (import as today).
    static func buildIndex(for dates: [Date], windowDays: Int = 1) async -> LibraryFingerprintIndex {
        guard await ensureReadAccess() else { return .empty }
        let window = TimeInterval(windowDays * 24 * 60 * 60)
        let assets = PHAsset.fetchAssets(with: .image, options: nil)
        var candidates: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            guard let created = asset.creationDate else { return }
            if dates.contains(where: { abs(created.timeIntervalSince($0)) <= window }) {
                candidates.append(asset)
            }
        }
        var hashes: [UInt64] = []
        for asset in candidates {
            guard let image = await thumbnail(for: asset),
                  let hash = ImageFingerprinter.fingerprint(image) else { continue }
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
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 64, height: 64),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
