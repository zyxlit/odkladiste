import Foundation
import CoreGraphics

/// Current persistent schema version for `AppState`.
public let currentSchemaVersion = 1

/// Root persisted application state.
public struct AppState: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var shelves: [Shelf]
    public var shelfOrder: [UUID]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        shelves: [Shelf] = [],
        shelfOrder: [UUID] = []
    ) {
        self.schemaVersion = schemaVersion
        self.shelves = shelves
        self.shelfOrder = shelfOrder
    }
}

/// Predefined calm accent colors for shelves.
public enum ShelfColor: String, Codable, CaseIterable, Sendable {
    case blue
    case purple
    case pink
    case orange
    case green
    case graphite
}

/// Layout mode of items inside a shelf window.
public enum DisplayMode: String, Codable, Sendable {
    case grid
    case list
}

/// Persisted window geometry anchored to a stable display identifier.
public struct WindowPlacement: Codable, Sendable, Equatable {
    /// Stable display UUID string (from `CGDisplayCreateUUIDFromDisplayID`), if available.
    public var displayUUID: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(displayUUID: String? = nil, x: Double, y: Double, width: Double, height: Double) {
        self.displayUUID = displayUUID
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(displayUUID: String? = nil, rect: CGRect) {
        self.displayUUID = displayUUID
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// A named collection of file references with its own independent panel state.
public struct Shelf: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var colorID: ShelfColor
    /// Optional user-defined `#RRGGBB` hex color overriding `colorID` when set.
    public var customColorHex: String?
    public var isPinned: Bool
    public var isVisible: Bool
    public var isAlwaysOnTop: Bool
    public var displayMode: DisplayMode
    public var windowPlacement: WindowPlacement?
    public var createdAt: Date
    public var updatedAt: Date
    public var items: [ShelfItem]

    public init(
        id: UUID = UUID(),
        name: String,
        colorID: ShelfColor = .blue,
        customColorHex: String? = nil,
        isPinned: Bool = false,
        isVisible: Bool = true,
        isAlwaysOnTop: Bool = true,
        displayMode: DisplayMode = .grid,
        windowPlacement: WindowPlacement? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        items: [ShelfItem] = []
    ) {
        self.id = id
        self.name = name
        self.colorID = colorID
        self.customColorHex = customColorHex
        self.isPinned = isPinned
        self.isVisible = isVisible
        self.isAlwaysOnTop = isAlwaysOnTop
        self.displayMode = displayMode
        self.windowPlacement = windowPlacement
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }

    /// Normalizes a 6-digit hex color string (with or without leading `#`) to `#RRGGBB`, or returns `nil`.
    public static func normalizedHex(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard stripped.count == 6,
              stripped.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return "#\(stripped.uppercased())"
    }
}

/// Kind of item stored in a shelf.
public enum ShelfItemKind: String, Codable, Sendable {
    case fileReference
}

/// A non-destructive reference to an existing file or directory on disk.
public struct ShelfItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: ShelfItemKind
    public var bookmarkData: Data?
    public var lastKnownURL: URL
    public var displayName: String
    /// Opaque stable file+volume identity string used for deduplication.
    public var resourceIdentity: String?
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        kind: ShelfItemKind = .fileReference,
        bookmarkData: Data? = nil,
        lastKnownURL: URL,
        displayName: String,
        resourceIdentity: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.bookmarkData = bookmarkData
        self.lastKnownURL = lastKnownURL
        self.displayName = displayName
        self.resourceIdentity = resourceIdentity
        self.addedAt = addedAt
    }

    /// Parent folder name used to disambiguate identically named files from different directories.
    public var parentFolderName: String {
        lastKnownURL.deletingLastPathComponent().lastPathComponent
    }
}

/// Runtime-only availability state of a referenced item.
public enum ItemAvailability: Sendable, Equatable {
    case available
    case temporarilyUnavailable
    case permissionRequired
    case missing
}

/// Per-item outcome inside an outgoing transfer transaction.
public enum TransferItemStatus: String, Sendable, Equatable {
    case pending
    case inProgress
    case confirmed
    case failed
    case cancelled
    case unverifiable
}

/// Direction/kind of outgoing transfer.
public enum TransferKind: String, Sendable, Equatable {
    case externalCopy
    case externalMove
    case internalShelfMove
    case internalShelfCopy
}

/// Immutable transaction snapshot for an outgoing drag/transfer operation.
public struct TransferOperation: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sourceShelfID: UUID
    public let itemIDs: [UUID]
    public var itemStatuses: [UUID: TransferItemStatus]
    public var kind: TransferKind?
    public var isFinalized: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceShelfID: UUID,
        itemIDs: [UUID],
        kind: TransferKind? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceShelfID = sourceShelfID
        self.itemIDs = itemIDs
        self.itemStatuses = Dictionary(uniqueKeysWithValues: itemIDs.map { ($0, .pending) })
        self.kind = kind
        self.isFinalized = false
        self.createdAt = createdAt
    }
}

/// Internal pasteboard payload for dragging items between Odkladiste shelves.
public struct InternalDragPayload: Codable, Sendable, Equatable {
    public static let pasteboardTypeIdentifier = "app.odkladiste.internal-items"

    public let formatVersion: Int
    public let operationID: UUID
    public let sourceShelfID: UUID
    public let itemIDs: [UUID]

    public init(
        formatVersion: Int = 1,
        operationID: UUID,
        sourceShelfID: UUID,
        itemIDs: [UUID]
    ) {
        self.formatVersion = formatVersion
        self.operationID = operationID
        self.sourceShelfID = sourceShelfID
        self.itemIDs = itemIDs
    }
}
