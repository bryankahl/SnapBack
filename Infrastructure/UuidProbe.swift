//
//  UuidProbe.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation
import ZIPFoundation

protocol UuidProbing {
    func probe(records: [MemoryRecord], zipURLs: [URL]) throws -> UuidProbeReport
}

final class UuidProbe: UuidProbing {
    func probe(records: [MemoryRecord], zipURLs: [URL]) throws -> UuidProbeReport {
        struct FileEntry {
            let key: String
            let file: MatchedFile
            let fileDate: String
            let isMain: Bool
        }
        var byUuid: [String: [FileEntry]] = [:]
        var byDashless: [String: [FileEntry]] = [:]
        for zipURL in zipURLs {
            let didStart = zipURL.startAccessingSecurityScopedResource()
            defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }
            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw ProbeError.cannotOpenArchive
            }
            for entry in archive {
                let path = entry.path
                guard path.hasPrefix("memories/") else { continue }
                guard !path.hasSuffix("/") else { continue }
                let base = (path as NSString).lastPathComponent
                let chars = Array(base)
                guard chars.count >= 47,
                      Self.isDatePrefix(String(chars.prefix(10))),
                      chars[10] == "_" else { continue }
                let uuidPart = String(chars[11..<47])
                guard Self.isUuid(uuidPart) else { continue }
                let isMain = base.contains("-main.")
                let isOverlay = base.contains("-overlay.")
                guard isMain || isOverlay else { continue }
                let key = uuidPart.lowercased()
                let fileEntry = FileEntry(
                    key: key,
                    file: MatchedFile(zipURL: zipURL, path: path),
                    fileDate: String(chars.prefix(10)),
                    isMain: isMain
                )
                byUuid[key, default: []].append(fileEntry)
                byDashless[key.replacingOccurrences(of: "-", with: ""), default: []].append(fileEntry)
            }
        }

        let dashedRegex = try NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
        let dashlessRegex = try NSRegularExpression(pattern: "[0-9a-fA-F]{32}")

        var withUuidMedia = 0
        var withUuidLink = 0
        var matched = 0
        var matchedMain = 0
        var matchedOverlayOnly = 0
        var noUuid = 0
        var uuidNoFile = 0
        var localEq = 0
        var utcEq = 0
        var neitherEq = 0
        var matchedKeys = Set<String>()

        for record in records {
            let mediaUuids = Self.extract(dashedRegex, from: record.mediaDownloadUrl).map { $0.lowercased() }
            let linkUuids = Self.extract(dashedRegex, from: record.downloadLink).map { $0.lowercased() }
            let dashlessMedia = Self.extract(dashlessRegex, from: record.mediaDownloadUrl).map { $0.lowercased() }
            let dashlessLink = Self.extract(dashlessRegex, from: record.downloadLink).map { $0.lowercased() }
            if !mediaUuids.isEmpty { withUuidMedia += 1 }
            if !linkUuids.isEmpty { withUuidLink += 1 }

            var entries: [FileEntry] = []
            for uuid in mediaUuids + linkUuids {
                if let hits = byUuid[uuid] { entries.append(contentsOf: hits) }
            }
            for uuid in dashlessMedia + dashlessLink {
                if let hits = byDashless[uuid] { entries.append(contentsOf: hits) }
            }
            for entry in entries { matchedKeys.insert(entry.key) }

            if entries.isEmpty {
                if mediaUuids.isEmpty && linkUuids.isEmpty && dashlessMedia.isEmpty && dashlessLink.isEmpty {
                    noUuid += 1
                } else {
                    uuidNoFile += 1
                }
                continue
            }
            matched += 1
            let first = entries.first(where: { $0.isMain }) ?? entries[0]
            if first.isMain { matchedMain += 1 } else { matchedOverlayOnly += 1 }
            if let date = Self.parseFormatter.date(from: record.dateString) {
                let localDate = Self.localDateFormatter.string(from: date)
                let utcDate = Self.utcDateFormatter.string(from: date)
                if localDate == first.fileDate { localEq += 1 }
                else if utcDate == first.fileDate { utcEq += 1 }
                else { neitherEq += 1 }
            } else {
                neitherEq += 1
            }
        }

        let orphans = byUuid.keys.filter { !matchedKeys.contains($0) }.count

        return UuidProbeReport(
            totalRecords: records.count,
            totalFilenameUuids: byUuid.count,
            recordsWithUuidInMediaUrl: withUuidMedia,
            recordsWithUuidInDownloadLink: withUuidLink,
            recordsMatchedToFile: matched,
            recordsMatchedToMain: matchedMain,
            recordsMatchedToOverlayOnly: matchedOverlayOnly,
            recordsWithNoUuidInUrls: noUuid,
            recordsWithUuidButNoFile: uuidNoFile,
            orphanFilenameUuids: orphans,
            matchedPairsLocalDateEquals: localEq,
            matchedPairsUtcDateEquals: utcEq,
            matchedPairsNeitherDateEquals: neitherEq
        )
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

    private static func extract(_ regex: NSRegularExpression, from s: String) -> [String] {
        let range = NSRange(s.startIndex..., in: s)
        return regex.matches(in: s, range: range).compactMap { match in
            guard let r = Range(match.range, in: s) else { return nil }
            return String(s[r])
        }
    }

    private static var parseFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return f
    }

    private static var localDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private static var utcDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    enum ProbeError: Error, LocalizedError {
        case cannotOpenArchive
        var errorDescription: String? { "Could not open one of the picked ZIPs." }
    }
}
