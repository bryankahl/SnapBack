//
//  ShapeCensus.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation
import ZIPFoundation

protocol ShapeCensusing {
    func census(records: [MemoryRecord], zipURLs: [URL]) throws -> ShapeCensusReport
}

final class ShapeCensus: ShapeCensusing {
    func census(records: [MemoryRecord], zipURLs: [URL]) throws -> ShapeCensusReport {
        var basenames: [String] = []
        var filesPerPart: [Int] = []
        for zipURL in zipURLs {
            let didStart = zipURL.startAccessingSecurityScopedResource()
            defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }
            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw CensusError.cannotOpenArchive
            }
            var count = 0
            for entry in archive {
                let path = entry.path
                guard path.hasPrefix("memories/") else { continue }
                guard !path.hasSuffix("/") else { continue }
                basenames.append((path as NSString).lastPathComponent)
                count += 1
            }
            filesPerPart.append(count)
        }

        var startsWithDate = 0
        var containsMain = 0
        var containsOverlay = 0
        var containsNeither = 0
        var shapeCounts: [String: Int] = [:]
        var postDateCounts: [String: Int] = [:]
        for base in basenames {
            let isMain = base.contains("-main.")
            let isOverlay = base.contains("-overlay.")
            if isMain { containsMain += 1 }
            if isOverlay { containsOverlay += 1 }
            if !isMain && !isOverlay { containsNeither += 1 }
            shapeCounts[Self.maskDigits(base), default: 0] += 1
            if Self.isDatePrefix(String(base.prefix(10))) {
                startsWithDate += 1
                if base.count >= 26 {
                    let post = String(base.dropFirst(10).prefix(16))
                    postDateCounts[Self.maskDigits(post), default: 0] += 1
                }
            }
        }

        let haystack = basenames.joined(separator: "\n")
        var dateAnywhere = 0
        var utcAnywhere = 0
        var localAnywhere = 0
        for record in records {
            let datePrefix = String(record.dateString.prefix(10))
            if !datePrefix.isEmpty && haystack.contains(datePrefix) { dateAnywhere += 1 }
            if let date = Self.parseFormatter.date(from: record.dateString) {
                let utcStem = Self.utcStemFormatter.string(from: date)
                if haystack.contains(utcStem) { utcAnywhere += 1 }
                let localStem = Self.localStemFormatter.string(from: date)
                if haystack.contains(localStem) { localAnywhere += 1 }
            }
        }

        let topShapes = shapeCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(10).map { ShapeCount(shape: $0.key, count: $0.value) }
        let topPostDate = postDateCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(5).map { ShapeCount(shape: $0.key, count: $0.value) }

        return ShapeCensusReport(
            partsPicked: zipURLs.count,
            filesPerPart: filesPerPart,
            totalMemoryFiles: basenames.count,
            startsWithDate: startsWithDate,
            containsMain: containsMain,
            containsOverlay: containsOverlay,
            containsNeither: containsNeither,
            dateAnywhereRecords: dateAnywhere,
            utcStemAnywhereRecords: utcAnywhere,
            localStemAnywhereRecords: localAnywhere,
            topShapes: topShapes,
            topPostDateShapes: topPostDate
        )
    }

    private static func isDatePrefix(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        let chars = Array(s)
        let digitPositions = [0, 1, 2, 3, 5, 6, 8, 9]
        for i in digitPositions where !chars[i].isNumber { return false }
        return chars[4] == "-" && chars[7] == "-"
    }

    private static func maskDigits(_ s: String) -> String {
        s.map { $0.isNumber ? "#" : String($0) }.joined()
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

    enum CensusError: Error, LocalizedError {
        case cannotOpenArchive
        var errorDescription: String? { "Could not open one of the picked ZIPs." }
    }
}
