//
//  MemoryMatch.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation

enum MatchStrategy {
    case utc
    case local
}

struct MatchedFile {
    let zipURL: URL
    let path: String
}

struct MemoryMatch {
    let record: MemoryRecord
    let mainFiles: [MatchedFile]
    let overlayFiles: [MatchedFile]
    let strategy: MatchStrategy
}

struct MatchAllReport {
    let totalRecords: Int
    let matchedUTC: Int
    let matchedLocal: Int
    let unmatched: Int
    let collisionGroups: Int
    let matchedWithOverlay: Int
    let totalMemoryFiles: Int
    let distinctDateTimeGroups: Int
    let unpatternedFiles: Int
}
