import Foundation

/// Outcome of resolving a `ShelfItem`'s bookmark or fallback URL.
public struct ResolvedItemURL: Sendable {
    public let url: URL
    public let availability: ItemAvailability
    public let refreshedBookmarkData: Data?
    public let updatedResourceIdentity: String?

    public init(
        url: URL,
        availability: ItemAvailability,
        refreshedBookmarkData: Data? = nil,
        updatedResourceIdentity: String? = nil
    ) {
        self.url = url
        self.availability = availability
        self.refreshedBookmarkData = refreshedBookmarkData
        self.updatedResourceIdentity = updatedResourceIdentity
    }
}

/// Handles URL bookmarks, stable file+volume identity extraction, and availability checks.
public struct BookmarkService: Sendable {
    public init() {}

    /// Extracts a stable identity string preferring `(volumeIdentifier, fileResourceIdentifier)`
    /// with fallback to standardized file path (preserving symlinks).
    public func resourceIdentity(for url: URL) -> String {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
        if let values = try? url.resourceValues(forKeys: keys),
           let fileID = values.fileResourceIdentifier as? NSData {
            let fileHex = (fileID as Data).map { String(format: "%02x", $0) }.joined()
            if let volID = values.volumeIdentifier as? NSData {
                let volHex = (volID as Data).map { String(format: "%02x", $0) }.joined()
                return "id:\(volHex):\(fileHex)"
            }
            return "id:local:\(fileHex)"
        }
        return "path:\(url.standardizedFileURL.path)"
    }

    /// Creates bookmark data for a file or directory URL.
    public func createBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [.isSymbolicLinkKey],
            relativeTo: nil
        )
    }

    /// Resolves a `ShelfItem` to its current URL and availability state.
    public func resolve(_ item: ShelfItem) -> ResolvedItemURL {
        if let bookmarkData = item.bookmarkData {
            var isStale = false
            do {
                let resolved = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withoutUI, .withoutMounting],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let exists = FileManager.default.fileExists(atPath: resolved.path)
                if exists {
                    let refreshed = isStale ? createBookmark(for: resolved) : nil
                    let identity = resourceIdentity(for: resolved)
                    return ResolvedItemURL(
                        url: resolved,
                        availability: .available,
                        refreshedBookmarkData: refreshed,
                        updatedResourceIdentity: identity
                    )
                }
            } catch {
                // Fall through to lastKnownURL check
            }
        }

        let fallbackURL = item.lastKnownURL
        let fm = FileManager.default
        if fm.fileExists(atPath: fallbackURL.path) {
            let refreshed = createBookmark(for: fallbackURL)
            let identity = resourceIdentity(for: fallbackURL)
            return ResolvedItemURL(
                url: fallbackURL,
                availability: .available,
                refreshedBookmarkData: refreshed,
                updatedResourceIdentity: identity
            )
        }

        // Distinguish disconnected external volume (/Volumes/<name>) vs missing file on mounted volume.
        let components = fallbackURL.pathComponents
        if components.count >= 3, components[1] == "Volumes" {
            let volumeMountPath = "/Volumes/\(components[2])"
            if !fm.fileExists(atPath: volumeMountPath) {
                return ResolvedItemURL(url: fallbackURL, availability: .temporarilyUnavailable)
            }
        }

        return ResolvedItemURL(url: fallbackURL, availability: .missing)
    }
}
