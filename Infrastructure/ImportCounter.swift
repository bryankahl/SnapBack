//
//  ImportCounter.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/31/26.
//

import Foundation
import ZIPFoundation

/// Counts dated mains for a picked set of ZIPs, using the real pairer.
/// Mirrors MemoryImporter's mains collection; the importer stays the single
/// writer — this only counts, so the product can decide free vs paywall.
enum ImportCounter {
    static func datedCount(records: [MemoryRecord], zipURLs: [URL], pairer: MemoryPairing) throws -> Int {
        let orderedURLs = zipURLs.sorted { partNumber($0) < partNumber($1) }
        var mains: [MatchedFile] = []
        for zipURL in orderedURLs {
            let didStart = zipURL.startAccessingSecurityScopedResource()
            defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }
            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw CounterError.cannotOpenArchive
            }
            for entry in archive {
                let path = entry.path
                guard path.hasPrefix("memories/") else { continue }
                guard !path.hasSuffix("/") else { continue }
                guard path.contains("-main.") else { continue }
                mains.append(MatchedFile(zipURL: zipURL, path: path))
            }
        }
        let (dated, _) = pairer.pair(records: records, mains: mains)
        return dated.count
    }

    private static func partNumber(_ url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-")
        if let last = parts.last, let n = Int(last) { return n }
        return 0
    }

    enum CounterError: Error, LocalizedError {
        case cannotOpenArchive

        var errorDescription: String? {
            "Could not open one of the picked ZIPs."
        }
    }
}
