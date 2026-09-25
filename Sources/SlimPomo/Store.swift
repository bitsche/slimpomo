import Foundation
import SlimPomoCore

struct Store {
    private let fileURL: URL

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
        return try? decoder.decode(Session.self, from: data)
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

    func save(_ session: Session) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
