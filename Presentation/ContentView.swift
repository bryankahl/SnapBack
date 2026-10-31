//
//  ContentView.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/27/26.
//

import SwiftUI

struct ContentView: View {
    let inspector: ExportInspecting
    let parser: MemoriesParsing
    let probe: MatchProbing
    let matcher: MemoryMatching
    let census: ShapeCensusing
    let uuidProbe: UuidProbing
    let linkProbe: LinkProbing
    let importer: MemoryImporting
    @State private var showingImportPicker = false
    @State private var importing = false
    @State private var importProgress = ""
    @State private var showingLinkPicker = false
    @State private var showingUuidPicker = false
    @State private var showingCensusPicker = false
    @State private var showingMatchPicker = false
    @State private var storedMatches: [MemoryMatch]?
    @State private var parsedRecords: [MemoryRecord]?
    @State private var showingProbePicker = false
    @State private var lastZipURL: URL?
    @State private var showingPicker = false
    @State private var reportText = "No ZIP inspected yet."
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SnapBack — Step 1")
                .font(.title2).bold()
            Text("Pick your Snapchat export ZIP. This only reads its structure — no photos are copied, modified, or uploaded.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Select export ZIP") { showingPicker = true }
                .buttonStyle(.borderedProminent)
            Text("Picked: \(lastZipURL?.lastPathComponent ?? "none")")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Parse records") {
                guard let url = lastZipURL else { return }
                do {
                    let (records, report) = try parser.parse(zipURL: url)
                    parsedRecords = records
                    reportText = formatParsed(report)
                    errorText = nil
                } catch {
                    errorText = "Parse failed: \(error.localizedDescription)"
                }
            }
            Button("Probe match") {
                showingProbePicker = true
            }
            .disabled(parsedRecords == nil)
            .disabled(lastZipURL == nil)
            
            Button("Match all parts") {
                showingMatchPicker = true
            }
            .disabled(parsedRecords == nil)
            Button("Census") {
                showingCensusPicker = true
            }
            .disabled(parsedRecords == nil)
            Button("UUID probe") {
                showingUuidPicker = true
            }
            .disabled(parsedRecords == nil)
            Button("Link probe") {
                showingLinkPicker = true
            }
            .disabled(parsedRecords == nil)
            Button("Import all") {
                showingImportPicker = true
            }
            .disabled(parsedRecords == nil || importing)
            Text(importProgress)
                .font(.footnote)
                .foregroundStyle(.secondary)





            ScrollView {
                Text(reportText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.callout)
            }
        }
        .padding()
        .sheet(isPresented: $showingPicker) {
            DocumentPicker { url in
                lastZipURL = url
                do {
                    let report = try inspector.inspect(zipURL: url)
                    reportText = format(report)
                    errorText = nil
                } catch {
                    errorText = "Inspection failed: \(error.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $showingProbePicker) {
            DocumentPicker { url in
                guard let records = parsedRecords else { return }
                do {
                    let report = try probe.probe(zipURL: url, records: records)
                    reportText = formatProbe(report)
                    errorText = nil
                } catch {
                    errorText = "Probe failed: \(error.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $showingMatchPicker) {
            MultiDocumentPicker { urls in
                guard let records = parsedRecords else { return }
                do {
                    let (matches, report) = try matcher.match(records: records, zipURLs: urls)
                    storedMatches = matches
                    reportText = formatMatchAll(report)
                    errorText = nil
                } catch {
                    errorText = "Match failed: \(error.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $showingCensusPicker) {
            MultiDocumentPicker { urls in
                guard let records = parsedRecords else { return }
                do {
                    let report = try census.census(records: records, zipURLs: urls)
                    reportText = formatCensus(report)
                    errorText = nil
                } catch {
                    errorText = "Census failed: \(error.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $showingUuidPicker) {
            MultiDocumentPicker { urls in
                guard let records = parsedRecords else { return }
                do {
                    let report = try uuidProbe.probe(records: records, zipURLs: urls)
                    reportText = formatUuid(report)
                    errorText = nil
                } catch {
                    errorText = "UUID probe failed: \(error.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $showingLinkPicker) {
            MultiDocumentPicker { urls in
                guard let records = parsedRecords else { return }
                do {
                    let report = try linkProbe.probe(records: records, zipURLs: urls)
                    reportText = formatLink(report)
                    errorText = nil
                } catch {
                    errorText = "Link probe failed: \(error.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $showingImportPicker) {
            MultiDocumentPicker { urls in
                guard let records = parsedRecords else { return }
                importing = true
                Task {
                    do {
                        let report = try await importer.importMains(records: records, zipURLs: urls, limit: 20, progress: { done, total in
                            Task { @MainActor in importProgress = "Imported \(done) / \(total)" }
                        })
                        await MainActor.run {
                            reportText = formatImport(report)
                            importing = false
                        }
                    } catch {
                        await MainActor.run {
                            errorText = "Import failed: \(error.localizedDescription)"
                            importing = false
                        }
                    }
                }
            }
        }





    }

    private func format(_ report: ExportStructureReport) -> String {
        var lines: [String] = []
        lines.append("Top-level entries: \(report.entryNames.joined(separator: ", "))")
        lines.append("Total entries: \(report.totalEntries)")
        lines.append("JSON file: \(report.jsonFileName ?? "not found")")
        lines.append("JSON top level: \(report.jsonTopLevel)")
        if let count = report.jsonEntryCount { lines.append("JSON entries: \(count)") }
        lines.append("JSON keys: \(report.jsonKeys.joined(separator: ", "))")
        if let count = report.recordCount { lines.append("Saved Media records: \(count)") }
        if !report.recordKeys.isEmpty {
            lines.append("Record keys: \(report.recordKeys.joined(separator: ", "))")
            for key in report.recordKeys {
                lines.append("  \(key): \(report.keyTypes[key] ?? "?")")
            }
        }

        return lines.joined(separator: "\n")
    }
    private func formatParsed(_ report: ParsedMemoriesReport) -> String {
        var lines: [String] = []
        lines.append("Records: \(report.recordCount)")
        lines.append("Dates parsed: \(report.dateParseSuccess), failed: \(report.dateParseFailure)")
        lines.append("Media types: \(report.distinctMediaTypes.joined(separator: ", "))")
        lines.append("Locations coordinate-like: \(report.locationCoordinateLike), other: \(report.locationOther)")
        lines.append("Exact record keys: \(report.exactRecordKeys.joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }
    private func formatProbe(_ report: MatchProbeReport) -> String {
        var lines: [String] = []
        lines.append("Files in part: \(report.fileCount)")
        for (ext, count) in report.filesByExtension.sorted(by: { $0.key < $1.key }) {
            lines.append(ext.isEmpty ? "  (no extension): \(count)" : "  .\(ext): \(count)")
        }
        lines.append("Distinct filename shapes: \(report.filenameShapes.count)")
        for shape in report.filenameShapes.prefix(10) {
            lines.append("  \(shape)")
        }
        lines.append("Records: \(report.totalRecords)")
        lines.append("Media Download Url basename matches: \(report.mediaUrlBasenameMatches)")
        lines.append("Download Link basename matches: \(report.downloadLinkBasenameMatches)")
        lines.append("Date-prefix matches: \(report.datePrefixMatches)")
        return lines.joined(separator: "\n")
    }
    private func formatMatchAll(_ report: MatchAllReport) -> String {
        var lines: [String] = []
        lines.append("Records: \(report.totalRecords)")
        lines.append("Matched via UTC stem: \(report.matchedUTC)")
        lines.append("Matched via local stem: \(report.matchedLocal)")
        lines.append("Unmatched: \(report.unmatched)")
        lines.append("Matched with >1 main file (same-second): \(report.collisionGroups)")
        lines.append("Matched with overlay: \(report.matchedWithOverlay)")
        lines.append("Memory files indexed: \(report.totalMemoryFiles)")
        lines.append("Distinct date-time groups: \(report.distinctDateTimeGroups)")
        lines.append("Unpatterned files: \(report.unpatternedFiles)")
        return lines.joined(separator: "\n")
    }
    private func formatCensus(_ report: ShapeCensusReport) -> String {
        var lines: [String] = []
        lines.append("Parts picked: \(report.partsPicked)")
        lines.append("Files per part: \(report.filesPerPart.map(String.init).joined(separator: ", "))")
        lines.append("Total memory files: \(report.totalMemoryFiles)")
        lines.append("Start with date: \(report.startsWithDate)")
        lines.append("Contain -main.: \(report.containsMain)")
        lines.append("Contain -overlay.: \(report.containsOverlay)")
        lines.append("Contain neither: \(report.containsNeither)")
        lines.append("Records with date anywhere: \(report.dateAnywhereRecords)")
        lines.append("Records with UTC stem anywhere: \(report.utcStemAnywhereRecords)")
        lines.append("Records with local stem anywhere: \(report.localStemAnywhereRecords)")
        lines.append("Top shapes:")
        for s in report.topShapes { lines.append("  \(s.count)x \(s.shape)") }
        lines.append("Top post-date shapes:")
        for s in report.topPostDateShapes { lines.append("  \(s.count)x \(s.shape)") }
        return lines.joined(separator: "\n")
    }
    private func formatUuid(_ report: UuidProbeReport) -> String {
        var lines: [String] = []
        lines.append("Records: \(report.totalRecords)")
        lines.append("Filename UUIDs: \(report.totalFilenameUuids)")
        lines.append("Records with UUID in Media URL: \(report.recordsWithUuidInMediaUrl)")
        lines.append("Records with UUID in Download Link: \(report.recordsWithUuidInDownloadLink)")
        lines.append("Records matched to file: \(report.recordsMatchedToFile)")
        lines.append("Matched to main: \(report.recordsMatchedToMain)")
        lines.append("Matched to overlay only: \(report.recordsMatchedToOverlayOnly)")
        lines.append("Records with no UUID in URLs: \(report.recordsWithNoUuidInUrls)")
        lines.append("Records with UUID but no file: \(report.recordsWithUuidButNoFile)")
        lines.append("Orphan filename UUIDs: \(report.orphanFilenameUuids)")
        lines.append("Matched pairs, local date ==: \(report.matchedPairsLocalDateEquals)")
        lines.append("Matched pairs, UTC date ==: \(report.matchedPairsUtcDateEquals)")
        lines.append("Matched pairs, neither ==: \(report.matchedPairsNeitherDateEquals)")
        return lines.joined(separator: "\n")
    }
    private func formatLink(_ report: LinkProbeReport) -> String {
        var lines: [String] = []
        lines.append("Image sample: \(report.imageSampleCount)")
        lines.append("Images with EXIF date: \(report.imagesWithExifDate)")
        lines.append("EXIF == record second (UTC): \(report.imagesMatchingRecordUtcSecond)")
        lines.append("EXIF day == record local day: \(report.imagesMatchingRecordLocalDay)")
        lines.append("JSON order: \(report.jsonOrder)")
        lines.append("Local days compared: \(report.localDaysCompared), match: \(report.localDaysMatch), mismatch: \(report.localDaysMismatch)")
        lines.append("UTC days compared: \(report.utcDaysCompared), match: \(report.utcDaysMatch), mismatch: \(report.utcDaysMismatch)")
        lines.append("Days records-no-files: \(report.daysRecordsNoFiles)")
        lines.append("Days files-no-records: \(report.daysFilesNoRecords)")
        return lines.joined(separator: "\n")
    }
    private func formatImport(_ report: ImportReport) -> String {
        var lines: [String] = []
        lines.append("Attempted: \(report.attempted)")
        lines.append("Imported: \(report.imported)")
        lines.append("Exact-dated: \(report.exactDated)")
        lines.append("Day-dated: \(report.dayDated)")
        lines.append("Failed: \(report.failed)")
        lines.append("Composited: \(report.composited)")
        lines.append("Video overlays skipped: \(report.videoOverlaysSkipped)")
        lines.append("Skipped (already imported): \(report.skippedAlreadyImported)")
        return lines.joined(separator: "\n")
    }






}

