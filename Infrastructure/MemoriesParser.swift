//
//  MemoriesParser.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation
import ZIPFoundation

protocol MemoriesParsing {
    func parse(zipURL: URL) throws -> (records: [MemoryRecord], report: ParsedMemoriesReport)
}

final class MemoriesParser: MemoriesParsing {
    func parse(zipURL: URL) throws -> (records: [MemoryRecord], report: ParsedMemoriesReport) {
        let didStart = zipURL.startAccessingSecurityScopedResource()
        defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }

        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw ParserError.cannotOpenArchive
        }

        var jsonEntry: Entry?
        var topLevel: [String] = []
        for entry in archive {
            let first = entry.path.split(separator: "/").first.map(String.init) ?? entry.path
            if !topLevel.contains(first) { topLevel.append(first) }
            if jsonEntry == nil && entry.path.lowercased().hasSuffix("memories_history.json") {
                jsonEntry = entry
            }
        }
        guard let jsonEntry = jsonEntry else { throw ParserError.jsonNotFound(found: topLevel) }

        var data = Data()
        _ = try archive.extract(jsonEntry, consumer: { data.append($0) })

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any],
              let savedKey = dict.keys.first(where: { $0.lowercased() == "saved media" }),
              let rawRecords = dict[savedKey] as? [[String: Any]] else {
            throw ParserError.unexpectedJsonShape
        }

        var records: [MemoryRecord] = []
        var dateSuccess = 0
        var dateFailure = 0
        var mediaTypes = Set<String>()
        var locationCoord = 0
        var locationOther = 0
        let formatter = Self.dateFormatter

        for raw in rawRecords {
            let record = MemoryRecord(
                dateString: Self.string(raw, "Date") ?? "",
                downloadLink: Self.string(raw, "Download Link") ?? "",
                locationString: Self.string(raw, "Location") ?? "",
                mediaDownloadUrl: Self.string(raw, "Media Download Url") ?? "",
                mediaTypeRaw: Self.string(raw, "Media Type") ?? "",
                exactKeys: raw.keys.sorted()
            )
            records.append(record)
            if formatter.date(from: record.dateString) != nil { dateSuccess += 1 } else { dateFailure += 1 }
            mediaTypes.insert(record.mediaTypeRaw)
            if Self.isCoordinateLike(record.locationString) { locationCoord += 1 } else { locationOther += 1 }
        }

        let report = ParsedMemoriesReport(
            recordCount: records.count,
            dateParseSuccess: dateSuccess,
            dateParseFailure: dateFailure,
            distinctMediaTypes: mediaTypes.sorted(),
            locationCoordinateLike: locationCoord,
            locationOther: locationOther,
            exactRecordKeys: records.first?.exactKeys ?? []
        )
        return (records, report)
    }

    private static func string(_ dict: [String: Any], _ key: String) -> String? {
        if let value = dict[key] as? String { return value }
        let found = dict.keys.first(where: { $0.lowercased() == key.lowercased() })
        return found.flatMap { dict[$0] as? String }
    }

    private static func isCoordinateLike(_ s: String) -> Bool {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, Double(parts[0]) != nil, Double(parts[1]) != nil else { return false }
        return true
    }

    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return f
    }

    enum ParserError: Error, LocalizedError {
        case cannotOpenArchive
        case jsonNotFound(found: [String])
        case unexpectedJsonShape

        var errorDescription: String? {
            switch self {
            case .cannotOpenArchive:
                return "Could not open this ZIP."
            case .jsonNotFound(let found):
                return "No memories_history.json in this ZIP. This file contains: \(found.joined(separator: ", ")). Pick the base part."
            case .unexpectedJsonShape:
                return "The JSON is not in the expected shape."
            }
        }
    }
}
