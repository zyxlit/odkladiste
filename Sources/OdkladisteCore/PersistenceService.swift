import Foundation

/// Outcome of loading persisted state, including any backup recovery notice.
public enum StateLoadNotice: Sendable, Equatable {
    case restoredFromBackup
    case corruptedBothPreserved
}

/// Result returned when loading `AppState` from disk.
public struct StateLoadResult: Sendable, Equatable {
    public let state: AppState
    public let notice: StateLoadNotice?

    public init(state: AppState, notice: StateLoadNotice? = nil) {
        self.state = state
        self.notice = notice
    }
}

/// Atomic JSON persistence with rolling backup and non-destructive corruption handling.
public final class PersistenceService: Sendable {
    public let baseDirectory: URL
    private let primaryURL: URL
    private let backupURL: URL

    public init(baseDirectory: URL? = nil) {
        let dir: URL
        if let baseDirectory {
            dir = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            dir = appSupport.appendingPathComponent("Odkladiste", isDirectory: true)
        }
        self.baseDirectory = dir
        self.primaryURL = dir.appendingPathComponent("state.json", isDirectory: false)
        self.backupURL = dir.appendingPathComponent("state.backup.json", isDirectory: false)
    }

    public func load() -> StateLoadResult {
        let fm = FileManager.default
        let decoder = Self.makeDecoder()

        if fm.fileExists(atPath: primaryURL.path) {
            do {
                let data = try Data(contentsOf: primaryURL)
                let state = try decoder.decode(AppState.self, from: data)
                return StateLoadResult(state: state, notice: nil)
            } catch {
                preserveCorruptedFile(at: primaryURL, prefix: "state.corrupted")
                if fm.fileExists(atPath: backupURL.path),
                   let backupData = try? Data(contentsOf: backupURL),
                   let backupState = try? decoder.decode(AppState.self, from: backupData) {
                    return StateLoadResult(state: backupState, notice: .restoredFromBackup)
                }
                if fm.fileExists(atPath: backupURL.path) {
                    preserveCorruptedFile(at: backupURL, prefix: "state.backup.corrupted")
                }
                return StateLoadResult(state: AppState(), notice: .corruptedBothPreserved)
            }
        }

        if fm.fileExists(atPath: backupURL.path),
           let backupData = try? Data(contentsOf: backupURL),
           let backupState = try? decoder.decode(AppState.self, from: backupData) {
            return StateLoadResult(state: backupState, notice: .restoredFromBackup)
        }

        return StateLoadResult(state: AppState(), notice: nil)
    }

    public func save(_ state: AppState) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let encoder = Self.makeEncoder()
        let data = try encoder.encode(state)

        let tempURL = baseDirectory.appendingPathComponent("state.tmp.\(UUID().uuidString).json")
        try data.write(to: tempURL, options: .atomic)

        if fm.fileExists(atPath: primaryURL.path) {
            if fm.fileExists(atPath: backupURL.path) {
                try? fm.removeItem(at: backupURL)
            }
            try? fm.copyItem(at: primaryURL, to: backupURL)
            _ = try fm.replaceItemAt(primaryURL, withItemAt: tempURL)
        } else {
            try fm.moveItem(at: tempURL, to: primaryURL)
        }
    }

    private func preserveCorruptedFile(at url: URL, prefix: String) {
        let fm = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dest = baseDirectory.appendingPathComponent("\(prefix).\(timestamp).json")
        try? fm.moveItem(at: url, to: dest)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
