//
//  MatchProbeReport.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation

/// Step 4 matcher probe report. Counts and masked shapes only — never
/// filenames, URLs, dates, or locations.
struct MatchProbeReport {
    let fileCount: Int
    let filesByExtension: [String: Int]
    let filenameShapes: [String]
    let mediaUrlBasenameMatches: Int
    let downloadLinkBasenameMatches: Int
    let datePrefixMatches: Int
    let totalRecords: Int
}
