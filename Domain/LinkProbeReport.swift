//
//  LinkProbeReport.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation

struct LinkProbeReport {
    let imageSampleCount: Int
    let imagesWithExifDate: Int
    let imagesMatchingRecordUtcSecond: Int
    let imagesMatchingRecordLocalDay: Int
    let jsonOrder: String
    let localDaysCompared: Int
    let localDaysMatch: Int
    let localDaysMismatch: Int
    let utcDaysCompared: Int
    let utcDaysMatch: Int
    let utcDaysMismatch: Int
    let daysRecordsNoFiles: Int
    let daysFilesNoRecords: Int
}
