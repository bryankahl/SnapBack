import SwiftUI

struct ProductView: View {
    let parser: MemoriesParsing
    let importer: MemoryImporting
    let pairer: MemoryPairing

    @StateObject private var store = PaywallStore()
    @State private var showingPicker = false
    @State private var importing = false
    @State private var progressText = ""
    @State private var progressDone = 0
    @State private var progressTotal = 0
    @State private var foundText: String?
    @State private var doneText: String?
    @State private var pausedText: String?
    @State private var errorText: String?
    @State private var showingPaywall = false
    @State private var paywallImportedSoFar = 0
    @State private var storedURLs: [URL]?
    @State private var storedRecords: [MemoryRecord]?

    static let trialLimit = 20

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("SnapBack")
                    .font(.largeTitle).bold()
                Text("SnapBack puts your Snapchat memories back into your camera roll, at the dates you took them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Select export ZIPs") { showingPicker = true }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(importing)
                    .opacity(importing ? 0.5 : 1)
                if let foundText {
                    Text(foundText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if importing {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(progressDone), total: Double(max(progressTotal, 1)))
                        Text(progressText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let doneText {
                    Text(doneText)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                if let pausedText {
                    Text(pausedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
        .sheet(isPresented: $showingPicker) {
            MultiDocumentPicker { urls in
                startImport(pickedURLs: urls)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(
                store: store,
                importedSoFar: paywallImportedSoFar,
                onUnlocked: {
                    showingPaywall = false
                    resumeAfterPurchase()
                },
                onClose: {
                    showingPaywall = false
                    pausedText = "Paused — \(paywallImportedSoFar) memories in your Photos. Tap again anytime to continue."
                }
            )
        }
    }

    private func startImport(pickedURLs: [URL]) {
        guard !pickedURLs.isEmpty, !importing else { return }
        importing = true
        progressText = "Starting…"
        progressDone = 0
        progressTotal = 0
        foundText = nil
        doneText = nil
        pausedText = nil
        errorText = nil
        storedURLs = pickedURLs
        do {
            let records = try parseFirst(pickedURLs: pickedURLs)
            storedRecords = records
        } catch {
            importing = false
            progressText = ""
            errorText = "Import failed: \(error.localizedDescription)"
            return
        }
        Task {
            do {
                guard let records = storedRecords else { return }
                await store.refreshPurchased()
                let purchased = await store.isPurchased
                let total = try ImportCounter.datedCount(records: records, zipURLs: pickedURLs, pairer: pairer)
                await MainActor.run { foundText = "Found \(total) memories." }
                if purchased || total <= Self.trialLimit {
                    let report = try await runImport(records: records, zipURLs: pickedURLs, limit: Int.max)
                    await finish(report: report)
                } else {
                    let report = try await runImport(records: records, zipURLs: pickedURLs, limit: Self.trialLimit)
                    await MainActor.run {
                        importing = false
                        progressText = ""
                        paywallImportedSoFar = report.imported + report.skippedAlreadyImported
                        showingPaywall = true
                    }
                }
            } catch {
                await MainActor.run {
                    importing = false
                    progressText = ""
                    errorText = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func resumeAfterPurchase() {
        guard let urls = storedURLs, let records = storedRecords, !importing else {
            errorText = "Couldn't resume — pick your export again."
            return
        }
        importing = true
        progressText = "Continuing…"
        progressDone = 0
        progressTotal = 0
        doneText = nil
        pausedText = nil
        errorText = nil
        Task {
            do {
                let report = try await runImport(records: records, zipURLs: urls, limit: Int.max)
                await finish(report: report)
            } catch {
                await MainActor.run {
                    importing = false
                    progressText = ""
                    errorText = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func runImport(records: [MemoryRecord], zipURLs: [URL], limit: Int) async throws -> ImportReport {
        try await importer.importMains(records: records, zipURLs: zipURLs, limit: limit, progress: { done, total in
            Task { @MainActor in
                progressDone = done
                progressTotal = total
                progressText = "Imported \(done) / \(total)"
            }
        })
    }

    private func finish(report: ImportReport) async {
        await MainActor.run {
            importing = false
            progressText = ""
            let total = report.imported + report.skippedAlreadyImported
            if report.failed > 0 {
                doneText = "Done — \(total) memories in your Photos. \(report.failed) couldn't be saved — run it again to retry."
            } else {
                doneText = "Done — \(total) memories in your Photos."
            }
        }
    }

    private func parseFirst(pickedURLs: [URL]) throws -> [MemoryRecord] {
        for url in pickedURLs {
            if let (records, _) = try? parser.parse(zipURL: url) {
                return records
            }
        }
        throw ProductError.memoriesNotFound
    }

    private enum ProductError: Error, LocalizedError {
        case memoriesNotFound

        var errorDescription: String? {
            "Couldn't find your memories in these ZIPs. Make sure you picked every part of your export, including the first one."
        }
    }
}
