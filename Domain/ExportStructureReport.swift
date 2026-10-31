//
//  ExportStructureReport.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/27/26.
//

import Foundation

/// What Steps 1+2 report about the export. Keys, counts, and types only — never
/// captions, locations, URLs, or message text. The report is safe to paste back.
struct ExportStructureReport {
    let entryNames: [String]
    let totalEntries: Int
    let jsonFileName: String?
    let jsonTopLevel: String
    let jsonKeys: [String]
    let jsonEntryCount: Int?
    // Step 2: shape of the "Saved Media" array, when the JSON has one.
    let recordCount: Int?
    let recordKeys: [String]
    let keyTypes: [String: String]
}
