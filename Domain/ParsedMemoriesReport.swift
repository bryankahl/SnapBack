//
//  ParsedMemoriesReport.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation

/// Step 3 verification report. Counts and patterns only — never values.
struct ParsedMemoriesReport {
    let recordCount: Int
    let dateParseSuccess: Int
    let dateParseFailure: Int
    let distinctMediaTypes: [String]
    let locationCoordinateLike: Int
    let locationOther: Int
    let exactRecordKeys: [String]
}
