//
//  MemoryRecord.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation

/// One "Saved Media" record. Keys are matched case-insensitively because
/// Step 2 only confirmed spellings approximately. Step 4 replaces this with
/// strict Codable once the exact spellings are confirmed by this step's report.
struct MemoryRecord {
    let dateString: String
    let downloadLink: String
    let locationString: String
    let mediaDownloadUrl: String
    let mediaTypeRaw: String
    /// Exact key spellings found in this record, for confirming the format.
    let exactKeys: [String]
}
