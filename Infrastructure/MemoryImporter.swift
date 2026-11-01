import Foundation
import Photos
import UIKit
import ZIPFoundation

struct ImportReport {
    let attempted: Int
    let imported: Int
    let exactDated: Int
    let dayDated: Int
    let failed: Int
    let composited: Int
    let videoOverlaysSkipped: Int
    let skippedAlreadyImported: Int
    let dedupSkipped: Int
}

protocol MemoryImporting {
    func importMains(records: [MemoryRecord], zipURLs: [URL], limit: Int, progress: @escaping (Int, Int) -> Void) async throws -> ImportReport
}

final class MemoryImporter: MemoryImporting {
    private let pairer: MemoryPairing
    private let skipKey = "importedFileKeys"
    static let dedupThreshold: Float = 0.3 // Starting point — calibrate after the run: loosen toward 0.5 if misses persist, tighten toward 0.15 if a memory goes missing (false skip).

    init(pairer: MemoryPairing) {
        self.pairer = pairer
    }

    func importMains(records: [MemoryRecord], zipURLs: [URL], limit: Int, progress: @escaping (Int, Int) -> Void) async throws -> ImportReport {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw ImportError.photoAccessDenied
        }

        let orderedURLs = zipURLs.sorted { Self.partNumber($0) < Self.partNumber($1) }
        var mains: [MatchedFile] = []
        var overlaysByUuid: [String: MatchedFile] = [:]
        for zipURL in orderedURLs {
            let didStart = zipURL.startAccessingSecurityScopedResource()
            defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }
            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw ImportError.cannotOpenArchive
            }
            for entry in archive {
                let path = entry.path
                guard path.hasPrefix("memories/") else { continue }
                guard !path.hasSuffix("/") else { continue }
                let file = MatchedFile(zipURL: zipURL, path: path)
                if path.contains("-main.") {
                    mains.append(file)
                } else if path.contains("-overlay.") {
                    if let uuid = Self.uuid(of: path) {
                        overlaysByUuid[uuid] = file
                    }
                }
            }
        }

        let (dated, _) = pairer.pair(records: records, mains: mains)
        let batch = Array(dated.prefix(limit))
        let photoIndex = await LibraryScanner.buildIndex()
        let videoIndex = await LibraryScanner.buildVideoIndex()
        let dedupIndex = LibraryDedupIndex(photos: photoIndex, videos: videoIndex)

        var importedKeys = Set(UserDefaults.standard.stringArray(forKey: skipKey) ?? [])
        var imported = 0, exact = 0, day = 0, failed = 0
        var composited = 0, videoOverlaysSkipped = 0, skipped = 0, attempted = 0, dedupSkipped = 0
        for (index, item) in batch.enumerated() {
            let key = Self.fileKey(item.file)
            if importedKeys.contains(key) {
                skipped += 1
                progress(index + 1, batch.count)
                continue
            }
            attempted += 1
            do {
                let overlay = overlaysByUuid[Self.uuid(of: item.file.path) ?? ""]
                switch try await save(item, overlay: overlay, dedupIndex: dedupIndex) {
                case .dedupSkipped:
                    dedupSkipped += 1
                case .saved(let didComposite):
                    if didComposite { composited += 1 }
                    if item.exact { exact += 1 } else { day += 1 }
                    if overlay != nil && Self.isVideo(item.file.path) { videoOverlaysSkipped += 1 }
                    imported += 1
                    importedKeys.insert(key)
                    UserDefaults.standard.set(Array(importedKeys), forKey: skipKey)
                }
            } catch {
                failed += 1
            }

            progress(index + 1, batch.count)
        }
        return ImportReport(
            attempted: attempted,
            imported: imported,
            exactDated: exact,
            dayDated: day,
            failed: failed,
            composited: composited,
            videoOverlaysSkipped: videoOverlaysSkipped,
            skippedAlreadyImported: skipped,
            dedupSkipped: dedupSkipped

        )
    }

    private enum SaveOutcome {
        case saved(composited: Bool)
        case dedupSkipped
    }

    private func save(_ item: DatedMain, overlay: MatchedFile?, dedupIndex: LibraryDedupIndex) async throws -> SaveOutcome {
        let mainURL = try extractToTmp(item.file)
        defer { try? FileManager.default.removeItem(at: mainURL) }
        let isVideo = Self.isVideo(item.file.path)
        if isVideo {
            if let frame = await VideoFrameExtractor.middleFrame(of: mainURL),
               let featurePrint = ImageFingerprinter.fingerprint(frame),
               dedupIndex.videos.hasCloseMatch(featurePrint, threshold: Self.dedupThreshold) {
                return .dedupSkipped
            }
            try await saveFile(at: mainURL, isVideo: true, creationDate: item.creationDate)
            return .saved(composited: false)
        }

        // Build the final image first: composited if an overlay applies,
        // otherwise the raw main. Dedup must fingerprint what actually gets
        // saved — fingerprinting the raw main never matches a library copy
        // that has the overlay baked in.
        var finalImage: UIImage?
        var didComposite = false
        if let overlay = overlay,
           let composited = try? composite(mainURL: mainURL, overlayFile: overlay) {
            finalImage = composited
            didComposite = true
        } else {
            finalImage = UIImage(contentsOfFile: mainURL.path)
        }
        if let finalImage,
           let featurePrint = ImageFingerprinter.fingerprint(finalImage),
           dedupIndex.photos.hasCloseMatch(featurePrint, threshold: Self.dedupThreshold) {
            return .dedupSkipped
        }
        if didComposite, let finalImage {
            try await saveImage(finalImage, creationDate: item.creationDate)
            return .saved(composited: true)
        }
        try await saveFile(at: mainURL, isVideo: false, creationDate: item.creationDate)
        return .saved(composited: false)
    }



    private func extractToTmp(_ file: MatchedFile) throws -> URL {
        let didStart = file.zipURL.startAccessingSecurityScopedResource()
        defer { if didStart { file.zipURL.stopAccessingSecurityScopedResource() } }
        guard let archive = Archive(url: file.zipURL, accessMode: .read) else {
            throw ImportError.cannotOpenArchive
        }
        guard let entry = archive.first(where: { $0.path == file.path }) else {
            throw ImportError.entryNotFound
        }
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent((file.path as NSString).lastPathComponent)
        try? FileManager.default.removeItem(at: tmpURL)
        var data = Data()
        _ = try archive.extract(entry, consumer: { data.append($0) })
        try data.write(to: tmpURL)
        return tmpURL
    }

    private func composite(mainURL: URL, overlayFile: MatchedFile) throws -> UIImage {
        guard let main = UIImage(contentsOfFile: mainURL.path) else { throw ImportError.undecodableImage }
        let overlayURL = try extractToTmp(overlayFile)
        defer { try? FileManager.default.removeItem(at: overlayURL) }
        guard let overlay = UIImage(contentsOfFile: overlayURL.path) else { throw ImportError.undecodableImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: main.size, format: format)
        return renderer.image { _ in
            main.draw(in: CGRect(origin: .zero, size: main.size))
            overlay.draw(in: CGRect(origin: .zero, size: main.size))
        }
    }

    private func saveImage(_ image: UIImage, creationDate: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                request.creationDate = creationDate
            }, completionHandler: { success, error in
                if let error = error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: ImportError.saveFailed) }
            })
        }
    }

    private func saveFile(at url: URL, isVideo: Bool, creationDate: Date) async throws {
        final class IDBox: @unchecked Sendable { var id: String? }
        let box = IDBox()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    if let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) {
                        request.creationDate = creationDate
                        box.id = request.placeholderForCreatedAsset?.localIdentifier
                    }
                } else {
                    if let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) {
                        request.creationDate = creationDate
                        box.id = request.placeholderForCreatedAsset?.localIdentifier
                    }
                }
            }, completionHandler: { success, error in
                if let error = error { continuation.resume(throwing: error) }
                else if success && box.id != nil { continuation.resume() }
                else { continuation.resume(throwing: ImportError.saveFailed) }
            })
        }
    }

    private static func isVideo(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "mp4" || ext == "mov"
    }

    private static func fileKey(_ file: MatchedFile) -> String {
        "\(file.zipURL.lastPathComponent)|\(file.path)"
    }

    private static func uuid(of path: String) -> String? {
        let base = (path as NSString).lastPathComponent
        let chars = Array(base)
        guard chars.count >= 47,
              isDatePrefix(String(chars.prefix(10))),
              chars[10] == "_" else { return nil }
        let uuidPart = String(chars[11..<47])
        guard isUuid(uuidPart) else { return nil }
        return uuidPart.lowercased()
    }

    private static func isDatePrefix(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        let chars = Array(s)
        let digitPositions = [0, 1, 2, 3, 5, 6, 8, 9]
        for i in digitPositions where !chars[i].isNumber { return false }
        return chars[4] == "-" && chars[7] == "-"
    }

    private static func isUuid(_ s: String) -> Bool {
        guard s.count == 36 else { return false }
        let chars = Array(s)
        let dashPositions = [8, 13, 18, 23]
        for i in 0..<36 {
            if dashPositions.contains(i) {
                if chars[i] != "-" { return false }
            } else if !chars[i].isHexDigit { return false }
        }
        return true
    }

    private static func partNumber(_ url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-")
        if let last = parts.last, let n = Int(last) { return n }
        return 0
    }

    enum ImportError: Error, LocalizedError {
        case cannotOpenArchive
        case entryNotFound
        case undecodableImage
        case saveFailed
        case photoAccessDenied

        var errorDescription: String? {
            switch self {
            case .cannotOpenArchive: return "Could not open one of the picked ZIPs."
            case .entryNotFound: return "A memory file was not found in its ZIP."
            case .undecodableImage: return "An image could not be decoded."
            case .saveFailed: return "Saving to the photo library failed."
            case .photoAccessDenied: return "Photo access denied — allow SnapBack to add photos in Settings."
            }
        }
    }
}
