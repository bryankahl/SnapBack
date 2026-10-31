//
//  MemoryMatcher.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation
import ZIPFoundation

protocol MemoryMatching {
    func match(records: [MemoryRecord], zipURLs: [URL]) throws -> (matches: [MemoryMatch], report: MatchAllReport)
}

final class MemoryMatcher: MemoryMatching {
    func match(records: [MemoryRecord], zipURLs: [URL]) throws -> (matches: [MemoryMatch], report: MatchAllReport) {
        var groups: [String: (mains: [MatchedFile], overlays: [MatchedFile])] = [:]
        var totalFiles = 0
        var unpatterned = 0

        for zipURL in zipURLs {
            let didStart = zipURL.startAccessingSecurityScopedResource()
            defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }
            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw MatcherError.cannotOpenArchive
            }
            for entry in archive {
                let path = entry.path
                guard path.hasPrefix("memories/") else { continue }
                guard !path.hasSuffix("/") else { continue }
                totalFiles += 1
                let base = (path as NSString).lastPathComponent
                guard base.count >= 17, Self.isDateTimePrefix(String(base.prefix(17))) else {
                    unpatterned += 1
                    continue
                }
                let stem = String(base.prefix(17))
                let file = MatchedFile(zipURL: zipURL, path: path)
                if base.contains("-overlay.") {
                    groups[stem, default: (mains: [], overlays: [])].overlays.append(file)
                } else if base.contains("-main.") {
                    groups[stem, default: (mains: [], overlays: [])].mains.append(file)
                } else {
                    unpatterned += 1
                }
            }
        }

        var matches: [MemoryMatch] = []
        var matchedUTC = 0
        var matchedLocal = 0
        var unmatched = 0
        var collisions = 0
        var withOverlay = 0

        for record in records {
            guard let date = Self.parseFormatter.date(from: record.dateString) else {
                unmatched += 1
                continue
            }
            let utcStem = Self.utcStemFormatter.string(from: date)
            let localStem = Self.localStemFormatter.string(from: date)
            if let group = groups[utcStem] {
                matchedUTC += 1
                if group.mains.count > 1 { collisions += 1 }
                if !group.overlays.isEmpty { withOverlay += 1 }
                matches.append(MemoryMatch(record: record, mainFiles: group.mains, overlayFiles: group.overlays, strategy: .utc))
            } else if let group = groups[localStem] {
                matchedLocal += 1
                if group.mains.count > 1 { collisions += 1 }
                if !group.overlays.isEmpty { withOverlay += 1 }
                matches.append(MemoryMatch(record: record, mainFiles: group.mains, overlayFiles: group.overlays, strategy: .local))
            } else {
                unmatched += 1
            }
        }

        let report = MatchAllReport(
            totalRecords: records.count,
            matchedUTC: matchedUTC,
            matchedLocal: matchedLocal,
            unmatched: unmatched,
            collisionGroups: collisions,
            matchedWithOverlay: withOverlay,
            totalMemoryFiles: totalFiles,
            distinctDateTimeGroups: groups.count,
            unpatternedFiles: unpatterned
        )
        return (matches, report)
    }

    private static func isDateTimePrefix(_ s: String) -> Bool {
        guard s.count == 17 else { return false }
        let chars = Array(s)
        let digitPositions = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 13, 14, 15, 16]
        for i in digitPositions where !chars[i].isNumber { return false }
        return chars[4] == "-" && chars[7] == "-" && chars[10] == "_"
    }

    private static var parseFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return f
    }

    private static var utcStemFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }

    private static var localStemFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }

    enum MatcherError: Error, LocalizedError {
        case cannotOpenArchive
        var errorDescription: String? { "Could not open one of the picked ZIPs." }
    }
}
