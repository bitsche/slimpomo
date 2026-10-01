import Foundation
import SlimPomoCore

/// Persists the session off the main thread. History is an append-only log; the session file omits it.
final class Store: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "app.slimpomo.store")
    private var pending: Session?
    private var firstQueued: Date?
    private var work: DispatchWorkItem?
    private var tailCount = 0
    private var tailID: UUID?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            #if SLIMPOMO_DEV
            let folder = "SlimPomo-dev"
            #else
            let folder = "SlimPomo"
            #endif
            self.fileURL = base.appendingPathComponent("\(folder)/session.json")
        }
    }

    func load() -> Session? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var session = try? decoder.decode(Session.self, from: data) else { return nil }
        let logged = Self.readLog(at: historyURL)
        if !logged.isEmpty {
            session.installHistory(logged)
            tailCount = logged.count
            tailID = logged.last?.id
        } else {
            // The session file still holds history until the first save copies it into the log.
            tailCount = 0
            tailID = nil
        }
        return session
    }

    /// Coalesces saves. A burst settles after 300 ms. A running timer still flushes within 2 s,
    /// so a crash keeps a recent remaining time. `flush` writes immediately.
    func save(_ session: Session) {
        let box = Snapshot(session: session)
        queue.async { [self] in
            if self.pending == nil {
                self.firstQueued = Date()
            }
            self.pending = box.session
            self.arm()
        }
    }

    /// Writes any pending snapshot before quit. Safe to call on the main thread.
    func flush() {
        queue.sync { [self] in
            work?.cancel()
            work = nil
            drain()
        }
    }

    /// Missing until the tour is finished or skipped. Quitting halfway leaves it missing.
    var tourSeen: Bool {
        FileManager.default.fileExists(atPath: tourURL.path)
    }

    func markTourSeen() {
        let directory = tourURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(#"{"tourSeen":true}"#.utf8).write(to: tourURL, options: .atomic)
    }

    func clearTourSeen() {
        try? FileManager.default.removeItem(at: tourURL)
    }

    private var tourURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("tour.json")
    }

    private var historyURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("history.jsonl")
    }

    private func arm() {
        let waited = firstQueued.map { Date().timeIntervalSince($0) } ?? 0
        if waited >= 2 {
            drain()
            return
        }
        work?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.drain()
        }
        work = item
        queue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func drain() {
        guard let session = pending else {
            firstQueued = nil
            return
        }
        pending = nil
        firstQueued = nil
        write(session)
    }

    private func write(_ session: Session) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writeHistory(session.history)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session.withoutHistory()) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func writeHistory(_ events: [HistoryEvent]) {
        let url = historyURL
        let rewrite = events.count < tailCount
            || (tailCount > 0 && (events.count < tailCount || events[tailCount - 1].id != tailID))
        let start = rewrite ? 0 : tailCount
        guard start <= events.count else { return }
        if start == events.count, !rewrite {
            return
        }
        let slice = events[start...]
        guard let data = Self.encodeLines(slice) else { return }
        let missing = !FileManager.default.fileExists(atPath: url.path)
        if rewrite || start == 0 || missing {
            let payload = (rewrite || missing) ? events[...] : slice
            guard let full = Self.encodeLines(payload) else { return }
            try? full.write(to: url, options: .atomic)
        } else if !data.isEmpty {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
        tailCount = events.count
        tailID = events.last?.id
    }

    private static func encodeLines(_ events: ArraySlice<HistoryEvent>) -> Data? {
        guard !events.isEmpty else { return Data() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for event in events {
            guard var line = try? encoder.encode(event) else { return nil }
            line.append(0x0A)
            data.append(line)
        }
        return data
    }

    private static func readLog(at url: URL) -> [HistoryEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var events: [HistoryEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(HistoryEvent.self, from: data) else { continue }
            events.append(event)
        }
        return events
    }
}

private struct Snapshot: @unchecked Sendable {
    let session: Session
}
