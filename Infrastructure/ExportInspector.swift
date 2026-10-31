//
//  ExportInspector.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/27/26.
//

import Foundation
import ZIPFoundation

/// Reads the export ZIP and reports its structure. Read-only: it never
/// modifies the ZIP and never writes media anywhere in Step 1.
protocol ExportInspecting {
    func inspect(zipURL: URL) throws -> ExportStructureReport
}

final class ExportInspector: ExportInspecting {
    func inspect(zipURL: URL) throws -> ExportStructureReport {
        // The file comes from the document picker in place (not copied),
        // so we hold security-scoped access while reading it.
        let didStart = zipURL.startAccessingSecurityScopedResource()
        defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }

        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw InspectorError.cannotOpenArchive
        }

        var entryNames: [String] = []
        var totalEntries = 0
        var jsonData: Data?
        var jsonFileName: String?

        for entry in archive {
            totalEntries += 1
            let top = entry.path.split(separator: "/").first.map(String.init) ?? entry.path
            if !entryNames.contains(top) { entryNames.append(top) }
            if entry.path.hasSuffix(".json") && jsonData == nil {
                jsonFileName = entry.path
                var data = Data()
                _ = try archive.extract(entry, consumer: { data.append($0) })
                jsonData = data
            }
        }

        var jsonTopLevel = "unknown"
        var jsonKeys: [String] = []
        var jsonEntryCount: Int?
        var recordCount: Int?
        var recordKeys: [String] = []
        var keyTypes: [String: String] = [:]


        if let jsonData {
            let object = try JSONSerialization.jsonObject(with: jsonData)
            if let array = object as? [[String: Any]] {
                jsonTopLevel = "array"
                jsonEntryCount = array.count
                jsonKeys = array.first?.keys.sorted() ?? []
            } else if let dict = object as? [String: Any] {
                jsonTopLevel = "dictionary"
                jsonKeys = dict.keys.sorted()
            }
            if let dict = object as? [String: Any],
               let savedKey = dict.keys.first(where: { $0.lowercased() == "saved media" }),
               let records = dict[savedKey] as? [[String: Any]] {
                recordCount = records.count
                let first = records.first ?? [:]
                recordKeys = first.keys.sorted()
                for (key, value) in first {
                    switch value {
                    case is String: keyTypes[key] = "string"
                    case is NSNumber: keyTypes[key] = "number"
                    case is [String: Any]: keyTypes[key] = "dictionary"
                    case is [Any]: keyTypes[key] = "array"
                    default: keyTypes[key] = "null"
                    }
                }
            }

        }

        return ExportStructureReport(
            entryNames: entryNames.sorted(),
            totalEntries: totalEntries,
            jsonFileName: jsonFileName,
            jsonTopLevel: jsonTopLevel,
            jsonKeys: jsonKeys,
            jsonEntryCount: jsonEntryCount,
            recordCount: recordCount,
            recordKeys: recordKeys,
            keyTypes: keyTypes
        )

    }

    enum InspectorError: Error {
        case cannotOpenArchive
    }
}
