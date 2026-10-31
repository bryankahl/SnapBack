//
//  MemoryPairer.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/30/26.
//

import Foundation

struct DatedMain {
    let file: MatchedFile
    let creationDate: Date
    let exact: Bool
}

protocol MemoryPairing {
    func pair(records: [MemoryRecord], mains: [MatchedFile]) -> (dated: [DatedMain], skippedFiles: Int)
}

final class MemoryPairer: MemoryPairing {
    func pair(records: [MemoryRecord], mains: [MatchedFile]) -> (dated: [DatedMain], skippedFiles: Int) {
        var recordGroups: [String: [(date: Date, type: String)]] = [:]
        for record in records {
            guard let date = Self.parseFormatter.date(from: record.dateString) else { continue }
            let day = Self.utcDateFormatter.string(from: date)
            recordGroups[day, default: []].append((date: date, type: Self.recordTypeLetter(record.mediaTypeRaw)))
        }

        var fileGroups: [String: [MatchedFile]] = [:]
        var skipped = 0
        for file in mains {
            let base = (file.path as NSString).lastPathComponent
            guard Self.isDatePrefix(String(base.prefix(10))) else { skipped += 1; continue }
            fileGroups[String(base.prefix(10)), default: []].append(file)
        }

        var dated: [DatedMain] = []
        for (day, files) in fileGroups {
            let fileSeq = files.map { Self.fileTypeLetter(($0.path as NSString).pathExtension.lowercased()) }
            if let recs = recordGroups[day], recs.map({ $0.type }) == fileSeq {
                for (rec, file) in zip(recs, files) {
                    dated.append(DatedMain(file: file, creationDate: rec.date, exact: true))
                }
            } else {
                let noon = Self.noonLocal(day: day)
                for file in files {
                    dated.append(DatedMain(file: file, creationDate: noon, exact: false))
                }
            }
        }
        dated.sort { $0.creationDate < $1.creationDate }
        return (dated, skipped)
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

    private static func noonLocal(day: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: "\(day) 12:00:00") ?? Date()
    }

    private static var parseFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return f
    }

    private static var utcDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
