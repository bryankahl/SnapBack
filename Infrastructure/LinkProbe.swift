//
//  LinkProbe.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation
import ZIPFoundation
import ImageIO

protocol LinkProbing {
    func probe(records: [MemoryRecord], zipURLs: [URL]) throws -> LinkProbeReport
}

final class LinkProbe: LinkProbing {
    func probe(records: [MemoryRecord], zipURLs: [URL]) throws -> LinkProbeReport {
        // Parts in export order: base first, then by -N suffix.
        let orderedURLs = zipURLs.sorted { Self.partNumber($0) < Self.partNumber($1) }

        // Record dates, parsed once.
        var recordDates: [Date] = []
        for record in records {
            if let date = Self.parseFormatter.date(from: record.dateString) {
                recordDates.append(date)
            }
        }
        let recordDateSet = Set(recordDates)
        let recordLocalDays = Set(recordDates.map { Self.localDateFormatter.string(from: $0) })

        // Test B prep: per-day type sequences.
        var recordLocalSeq: [String: [String]] = [:]
        var recordUtcSeq: [String: [String]] = [:]
        for record in records {
            guard let date = Self.parseFormatter.date(from: record.dateString) else { continue }
            let typeLetter = Self.recordTypeLetter(record.mediaTypeRaw)
            recordLocalSeq[Self.localDateFormatter.string(from: date), default: []].append(typeLetter)
            recordUtcSeq[Self.utcDateFormatter.string(from: date), default: []].append(typeLetter)
        }

        var fileLocalSeq: [String: [String]] = [:]
        var exifDates: [Date] = []
        var imageSampled = 0

        for zipURL in orderedURLs {
            let didStart = zipURL.startAccessingSecurityScopedResource()
            defer { if didStart { zipURL.stopAccessingSecurityScopedResource() } }
            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw ProbeError.cannotOpenArchive
            }
            for entry in archive {
                let path = entry.path
                guard path.hasPrefix("memories/") else { continue }
                guard !path.hasSuffix("/") else { continue }
                let base = (path as NSString).lastPathComponent
                guard base.contains("-main.") else { continue }
                let ext = (base as NSString).pathExtension.lowercased()
                let typeLetter = Self.fileTypeLetter(ext)
                guard typeLetter != "O" else { continue }
                guard Self.isDatePrefix(String(base.prefix(10))) else { continue }
                let fileDate = String(base.prefix(10))
                fileLocalSeq[fileDate, default: []].append(typeLetter)

                // Test A: sample the first 100 image mains for EXIF dates.
                if imageSampled < 100 && (ext == "jpg" || ext == "jpeg" || ext == "png") {
                    imageSampled += 1
                    var data = Data()
                    if (try? archive.extract(entry, consumer: { data.append($0) })) != nil,
                       let exifDate = Self.exifDate(from: data) {
                        exifDates.append(exifDate)
                    }
                }
            }
        }

        let imagesWithExif = exifDates.count
        let matchSecond = exifDates.filter { recordDateSet.contains($0) }.count
        let matchDay = exifDates.filter { recordLocalDays.contains(Self.localDateFormatter.string(from: $0)) }.count

        let jsonOrder: String
        if zip(recordDates, recordDates.dropFirst()).allSatisfy({ $0 <= $1 }) {
            jsonOrder = "ascending"
        } else if zip(recordDates, recordDates.dropFirst()).allSatisfy({ $0 >= $1 }) {
            jsonOrder = "descending"
        } else {
            jsonOrder = "mixed"
        }

        var localCompared = 0, localMatch = 0, localMismatch = 0
        for (day, seq) in fileLocalSeq {
            guard let recordSeq = recordLocalSeq[day] else { continue }
            localCompared += 1
            if seq == recordSeq { localMatch += 1 } else { localMismatch += 1 }
        }
        var utcCompared = 0, utcMatch = 0, utcMismatch = 0
        for (day, seq) in fileLocalSeq {
            guard let recordSeq = recordUtcSeq[day] else { continue }
            utcCompared += 1
            if seq == recordSeq { utcMatch += 1 } else { utcMismatch += 1 }
        }
        let recordsNoFiles = recordLocalSeq.keys.filter { fileLocalSeq[$0] == nil }.count
        let filesNoRecords = fileLocalSeq.keys.filter { recordLocalSeq[$0] == nil }.count

        return LinkProbeReport(
            imageSampleCount: imageSampled,
            imagesWithExifDate: imagesWithExif,
            imagesMatchingRecordUtcSecond: matchSecond,
            imagesMatchingRecordLocalDay: matchDay,
            jsonOrder: jsonOrder,
            localDaysCompared: localCompared,
            localDaysMatch: localMatch,
            localDaysMismatch: localMismatch,
            utcDaysCompared: utcCompared,
            utcDaysMatch: utcMatch,
            utcDaysMismatch: utcMismatch,
            daysRecordsNoFiles: recordsNoFiles,
            daysFilesNoRecords: filesNoRecords
        )
    }

    private static func partNumber(_ url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-")
        if let last = parts.last, let n = Int(last) { return n }
        return 0
    }

    private static func recordTypeLetter(_ mediaType: String) -> String {
        mediaType.lowercased() == "video" ? "V" : "I"
    }

    private static func fileTypeLetter(_ ext: String) -> String {
        switch ext {
        case "jpg", "jpeg", "png", "webp": return "I"
        case "mp4", "mov": return "V"
        default: return "O"
        }
    }

    private static func isDatePrefix(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        let chars = Array(s)
        let digitPositions = [0, 1, 2, 3, 5, 6, 8, 9]
        for i in digitPositions where !chars[i].isNumber { return false }
        return chars[4] == "-" && chars[7] == "-"
    }

    private static func exifDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
        let formatter = Self.exifFormatter
        if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let d = formatter.date(from: s) { return d }
        if let s = exif[kCGImagePropertyExifDateTimeDigitized] as? String,
           let d = formatter.date(from: s) { return d }
        return nil
    }

    private static var exifFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }

    private static var parseFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return f
    }

    private static var localDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private static var utcDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    enum ProbeError: Error, LocalizedError {
        case cannotOpenArchive
        var errorDescription: String? { "Could not open one of the picked ZIPs." }
    }
}
