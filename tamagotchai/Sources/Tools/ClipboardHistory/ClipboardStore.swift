import Foundation
import os

/// Persists clipboard history entries to disk.
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    private let logger = Logger(
        subsystem: "com.unstablemind.tamagotchai",
        category: "clipboard-store"
    )

    private(set) var entries: [ClipboardEntry] = []
    private let maxEntries = 200

    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("com.unstablemind.tamagotchai")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("clipboard-history.json")
    }()

    private init() {
        load()
    }

    func add(_ entry: ClipboardEntry) {
        // Deduplicate: skip if the last entry has identical text content
        if let last = entries.first,
           last.contentType == entry.contentType,
           last.textContent == entry.textContent,
           entry.contentType == .text
        {
            return
        }

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func allEntries() -> [ClipboardEntry] {
        entries
    }

    func search(query: String) -> [ClipboardEntry] {
        guard !query.isEmpty else { return entries }
        let lowered = query.lowercased()
        return entries.filter { entry in
            entry.preview.lowercased().contains(lowered)
        }
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.error("Failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            entries = try JSONDecoder().decode([ClipboardEntry].self, from: data)
            // swiftformat:disable:next redundantSelf
            logger.info("Loaded \(self.entries.count) clipboard entries")
        } catch {
            logger.error("Failed to load clipboard history: \(error.localizedDescription)")
        }
    }
}
