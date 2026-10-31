//
//  MatchProbe.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation
import ZIPFoundation

protocol MatchProbing {
    func probe(zipURL: URL, records: [MemoryRecord]) throws -> MatchProbeReport
}

final class MatchProbe: MatchProbing {
    func probe(zipURL: URL, records: [MemoryRecord]) throws -> MatchProbeReport {
        let didStart = zipURL.startAccessingSecurityScopedResource()
        defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }

        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw ProbeError.cannotOpenArchive
        }
        var basenames: [String] = []
        var byExtension: [String: Int] = [:]
        var shapes = Set<String>()
        for entry in archive {
            let path = entry.path
            guard path.hasPrefix("memories/") || path.hasPrefix("chat_media/") else { continue }
            guard !path.hasSuffix("/") else { continue }
            let base = (path as NSString).lastPathComponent
            basenames.append(base)
            let ext = (base as NSString).pathExtension.lowercased()
            byExtension[ext, default: 0] += 1
            shapes.insert(Self.maskDigits(base))
        }
        let basenameSet = Set(basenames)

        var mediaUrlMatches = 0
        var downloadLinkMatches = 0
        var datePrefixMatches = 0
        for record in records {
            let mediaBase = Self.urlBasename(record.mediaDownloadUrl)
            if !mediaBase.isEmpty && basenameSet.contains(mediaBase) { mediaUrlMatches += 1 }
            let linkBase = Self.urlBasename(record.downloadLink)
            if !linkBase.isEmpty && basenameSet.contains(linkBase) { downloadLinkMatches += 1 }
            let datePrefix = String(record.dateString.prefix(10))
            if !datePrefix.isEmpty && basenames.contains(where: { $0.hasPrefix(datePrefix) }) { datePrefixMatches += 1 }
        }

        return MatchProbeReport(
            fileCount: basenames.count,
            filesByExtension: byExtension,
            filenameShapes: shapes.sorted(),
            mediaUrlBasenameMatches: mediaUrlMatches,
            downloadLinkBasenameMatches: downloadLinkMatches,
            datePrefixMatches: datePrefixMatches,
            totalRecords: records.count
        )
    }

    private static func urlBasename(_ s: String) -> String {
        if let url = URL(string: s) { return url.lastPathComponent }
        return (s as NSString).lastPathComponent
    }

    private static func maskDigits(_ s: String) -> String {
        s.map { $0.isNumber ? "#" : String($0) }.joined()
    }

    enum ProbeError: Error {
        case cannotOpenArchive
    }
}
