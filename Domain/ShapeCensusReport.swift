//
//  ShapeCensusReport.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation

struct ShapeCount {
    let shape: String
    let count: Int
}

struct ShapeCensusReport {
    let partsPicked: Int
    let filesPerPart: [Int]
    let totalMemoryFiles: Int
    let startsWithDate: Int
    let containsMain: Int
    let containsOverlay: Int
    let containsNeither: Int
    let dateAnywhereRecords: Int
    let utcStemAnywhereRecords: Int
    let localStemAnywhereRecords: Int
    let topShapes: [ShapeCount]
    let topPostDateShapes: [ShapeCount]
}
