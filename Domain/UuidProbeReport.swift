//
//  UuidProbeReport.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation

struct UuidProbeReport {
    let totalRecords: Int
    let totalFilenameUuids: Int
    let recordsWithUuidInMediaUrl: Int
    let recordsWithUuidInDownloadLink: Int
    let recordsMatchedToFile: Int
    let recordsMatchedToMain: Int
    let recordsMatchedToOverlayOnly: Int
    let recordsWithNoUuidInUrls: Int
    let recordsWithUuidButNoFile: Int
    let orphanFilenameUuids: Int
    let matchedPairsLocalDateEquals: Int
    let matchedPairsUtcDateEquals: Int
    let matchedPairsNeitherDateEquals: Int
}
