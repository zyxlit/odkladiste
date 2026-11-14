import Foundation
import Combine

/// Summary of an add-files drop operation.
public struct AddFilesResult: Sendable, Equatable {
    public let addedIDs: [UUID]
    public let duplicateIDs: [UUID]
    public let rejectedCount: Int

    public init(addedIDs: [UUID], duplicateIDs: [UUID], rejectedCount: Int) {
        self.addedIDs = addedIDs
        self.duplicateIDs = duplicateIDs
        self.rejectedCount = rejectedCount
    }
}

/// Diagnostic event logged during Etapa A prototype testing.
public struct PrototypeDiagnosticEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String

    public init(message: String, timestamp: Date = Date()) {
        self.message = message
        self.timestamp = timestamp
    }
}

/// Central `@MainActor` store for shelves, items, persistence, and transfer transactions.
@MainActor
public final class ShelfStore: ObservableObject {
    @Published public private(set) var state: AppState
    @Published public private(set) var availabilityByItemID: [UUID: ItemAvailability] = [:]
    @Published public private(set) var highlightedItemID: UUID?
    @Published public private(set) var activeTransfers: [UUID: TransferOperation] = [:]
    @Published public private(set) var unverifiableTransfers: [TransferOperation] = []
    @Published public private(set) var loadNotice: StateLoadNotice?
    @Published public private(set) var diagnostics: [PrototypeDiagnosticEvent] = []
    @Published public private(set) var canUndo: Bool = false
    @Published public private(set) var canRedo: Bool = false

    private let persistence: PersistenceService
    private let bookmarkService: BookmarkService
    private var saveTask: Task<Void, Never>?
    private var defaultShelfPrefix: String
    private var undoStack: [AppStateSnapshot] = []
    private var redoStack: [AppStateSnapshot] = []

    private struct AppStateSnapshot {
        let state: AppState
        let label: String
    }

    public init(
        persistence: PersistenceService = PersistenceService(),
        bookmarkService: BookmarkService = BookmarkService(),
        defaultShelfPrefix: String = "Polička",
        bootstrapPrototypeShelvesIfEmpty: Bool = true
    ) {
        self.persistence = persistence
        self.bookmarkService = bookmarkService
        self.defaultShelfPrefix = defaultShelfPrefix

        let loaded = persistence.load()
        self.state = loaded.state
        self.loadNotice = loaded.notice

        if bootstrapPrototypeShelvesIfEmpty && self.state.shelves.isEmpty {
            let first = createShelfObject(name: nextDefaultShelfName(), color: .blue)
            self.state.shelves = [first]
            self.state.shelfOrder = [first.id]
            scheduleSave()
        }

        refreshAllAvailability()
    }

    // MARK: - Shelf Management

    public var orderedShelves: [Shelf] {
        let byID = Dictionary(uniqueKeysWithValues: state.shelves.map { ($0.id, $0) })
        var result: [Shelf] = []
        var seen = Set<UUID>()
        for id in state.shelfOrder {
            if let shelf = byID[id] {
                result.append(shelf)
                seen.insert(id)
            }
        }
        for shelf in state.shelves where !seen.contains(shelf.id) {
            result.append(shelf)
        }
        return result
    }

    @discardableResult
    public func createShelf(
        name: String? = nil,
        color: ShelfColor = .blue,
        placement: WindowPlacement? = nil
    ) -> Shelf {
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (resolvedName?.isEmpty == false) ? resolvedName! : nextDefaultShelfName()
        let shelf = createShelfObject(name: finalName, color: color, placement: placement)
        state.shelves.append(shelf)
        state.shelfOrder.append(shelf.id)
        scheduleSave()
        log("Vytvořena polička '\(shelf.name)'")
        return shelf
    }

    public func renameShelf(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = shelfIndex(id) else { return }
        state.shelves[idx].name = trimmed
        state.shelves[idx].updatedAt = Date()
        scheduleSave()
    }

    public func setShelfColor(id: UUID, color: ShelfColor) {
        guard let idx = shelfIndex(id) else { return }
        state.shelves[idx].colorID = color
        state.shelves[idx].customColorHex = nil
        state.shelves[idx].updatedAt = Date()
        scheduleSave()
    }

    @discardableResult
    public func setShelfCustomColorHex(id: UUID, hex: String) -> Bool {
        guard let idx = shelfIndex(id),
              let normalized = Shelf.normalizedHex(hex) else {
            return false
        }
        state.shelves[idx].customColorHex = normalized
        state.shelves[idx].updatedAt = Date()
        scheduleSave()
        return true
    }

    public func setShelfVisible(id: UUID, isVisible: Bool) {
        guard let idx = shelfIndex(id) else { return }
        state.shelves[idx].isVisible = isVisible
        state.shelves[idx].updatedAt = Date()
        scheduleSave()
    }

    public func setShelfAlwaysOnTop(id: UUID, isAlwaysOnTop: Bool) {
        guard let idx = shelfIndex(id) else { return }
        state.shelves[idx].isAlwaysOnTop = isAlwaysOnTop
        state.shelves[idx].updatedAt = Date()
        scheduleSave()
    }

    public func setShelfPinned(id: UUID, isPinned: Bool) {
        guard let idx = shelfIndex(id) else { return }
        state.shelves[idx].isPinned = isPinned
        state.shelves[idx].updatedAt = Date()
        scheduleSave()
    }

    public func setDisplayMode(id: UUID, mode: DisplayMode) {
        guard let idx = shelfIndex(id) else { return }
        state.shelves[idx].displayMode = mode
        state.shelves[idx].updatedAt = Date()
        scheduleSave()
    }

    public func moveShelf(id: UUID, direction: Int) {
        var order = orderedShelves.map(\.id)
        guard let currentIndex = order.firstIndex(of: id) else { return }
        let targetIndex = currentIndex + direction
        guard targetIndex >= 0 && targetIndex < order.count else { return }
        order.swapAt(currentIndex, targetIndex)
        state.shelfOrder = order
        scheduleSave()
    }

    public func updatePlacement(for shelfID: UUID, placement: WindowPlacement) {
        guard let idx = shelfIndex(shelfID) else { return }
        state.shelves[idx].windowPlacement = placement
        scheduleSave()
    }

    public func emptyShelf(id: UUID) {
        guard let idx = shelfIndex(id), !state.shelves[idx].items.isEmpty else { return }
        recordUndo(label: "Vyprázdnit poličku")
        let removedIDs = state.shelves[idx].items.map(\.id)
        state.shelves[idx].items.removeAll()
        state.shelves[idx].updatedAt = Date()
        for itemID in removedIDs {
            availabilityByItemID.removeValue(forKey: itemID)
        }
        scheduleSave()
        log("Vyprázdněna polička '\(state.shelves[idx].name)' (\(removedIDs.count) odkazů)")
    }

    public func deleteShelf(id: UUID) {
        guard let idx = shelfIndex(id) else { return }
        let removed = state.shelves.remove(at: idx)
        state.shelfOrder.removeAll { $0 == id }
        for item in removed.items {
            availabilityByItemID.removeValue(forKey: item.id)
        }
        scheduleSave()
        log("Odstraněna polička '\(removed.name)'")
    }

    // MARK: - Items

    @discardableResult
    public func addFileURLs(_ urls: [URL], to shelfID: UUID) -> AddFilesResult {
        guard let idx = shelfIndex(shelfID) else {
            return AddFilesResult(addedIDs: [], duplicateIDs: [], rejectedCount: urls.count)
        }

        let fm = FileManager.default
        var addedItems: [ShelfItem] = []
        var duplicateIDs: [UUID] = []
        var rejectedCount = 0

        for url in urls {
            guard url.isFileURL, fm.fileExists(atPath: url.path) else {
                rejectedCount += 1
                continue
            }

            let identity = bookmarkService.resourceIdentity(for: url)
            if let existing = state.shelves[idx].items.first(where: { matchesIdentity($0, identity: identity, url: url) })
                ?? addedItems.first(where: { matchesIdentity($0, identity: identity, url: url) }) {
                duplicateIDs.append(existing.id)
                highlightedItemID = existing.id
                continue
            }

            let bookmark = bookmarkService.createBookmark(for: url)
            let item = ShelfItem(
                kind: .fileReference,
                bookmarkData: bookmark,
                lastKnownURL: url,
                displayName: url.lastPathComponent,
                resourceIdentity: identity
            )
            addedItems.append(item)
        }

        let addedIDs = addedItems.map(\.id)
        if !addedItems.isEmpty {
            recordUndo(label: "Přidat položky")
            state.shelves[idx].items.append(contentsOf: addedItems)
            for item in addedItems {
                availabilityByItemID[item.id] = .available
            }
            state.shelves[idx].updatedAt = Date()
            scheduleSave()
            log("Přidáno \(addedIDs.count) položek do '\(state.shelves[idx].name)' (duplicit: \(duplicateIDs.count), odmítnuto: \(rejectedCount))")
        } else if !duplicateIDs.isEmpty {
            log("Duplicitní položky v '\(state.shelves[idx].name)': \(duplicateIDs.count)")
        }

        return AddFilesResult(addedIDs: addedIDs, duplicateIDs: duplicateIDs, rejectedCount: rejectedCount)
    }

    public func removeItems(ids: [UUID], from shelfID: UUID, recordUndoStep: Bool = true) {
        guard let idx = shelfIndex(shelfID), !ids.isEmpty else { return }
        let idSet = Set(ids)
        let hasMatch = state.shelves[idx].items.contains { idSet.contains($0.id) }
        guard hasMatch else { return }
        if recordUndoStep {
            recordUndo(label: "Odebrat položky")
        }
        let before = state.shelves[idx].items.count
        state.shelves[idx].items.removeAll { idSet.contains($0.id) }
        for id in ids {
            availabilityByItemID.removeValue(forKey: id)
        }
        if state.shelves[idx].items.count != before {
            state.shelves[idx].updatedAt = Date()
            scheduleSave()
        }
    }

    public func refreshAllAvailability() {
        for sIdx in state.shelves.indices {
            var modified = false
            for iIdx in state.shelves[sIdx].items.indices {
                let item = state.shelves[sIdx].items[iIdx]
                let resolved = bookmarkService.resolve(item)
                availabilityByItemID[item.id] = resolved.availability
                if resolved.availability == .available {
                    if state.shelves[sIdx].items[iIdx].lastKnownURL != resolved.url {
                        state.shelves[sIdx].items[iIdx].lastKnownURL = resolved.url
                        state.shelves[sIdx].items[iIdx].displayName = resolved.url.lastPathComponent
                        modified = true
                    }
                    if let refreshed = resolved.refreshedBookmarkData {
                        state.shelves[sIdx].items[iIdx].bookmarkData = refreshed
                        modified = true
                    }
                    if let identity = resolved.updatedResourceIdentity,
                       state.shelves[sIdx].items[iIdx].resourceIdentity != identity {
                        state.shelves[sIdx].items[iIdx].resourceIdentity = identity
                        modified = true
                    }
                }
            }
            if modified {
                state.shelves[sIdx].updatedAt = Date()
            }
        }
    }

    // MARK: - Transfer Transactions (Section 7.3.1 & 7.4)

    public func beginTransfer(from shelfID: UUID, itemIDs: [UUID]) -> TransferOperation {
        let operation = TransferOperation(sourceShelfID: shelfID, itemIDs: itemIDs)
        activeTransfers[operation.id] = operation
        log("Zahájen přenos \(operation.id.uuidString.prefix(8)) (\(itemIDs.count) položek)")
        return operation
    }

    /// Completes an outgoing external drag session. Idempotent for repeated callbacks.
    public func completeExternalTransfer(
        operationID: UUID,
        dragOutcome: ExternalDragOutcome
    ) {
        guard var op = activeTransfers[operationID], !op.isFinalized else {
            return
        }

        op.isFinalized = true

        switch dragOutcome {
        case .cancelled:
            for id in op.itemIDs {
                op.itemStatuses[id] = .cancelled
            }
            activeTransfers[operationID] = op
            log("Přenos \(operationID.uuidString.prefix(8)) zrušen/odmítnut — položky zachovány")

        case .copyConfirmed:
            op.kind = .externalCopy
            for id in op.itemIDs {
                op.itemStatuses[id] = .confirmed
            }
            activeTransfers[operationID] = op
            removeItems(ids: op.itemIDs, from: op.sourceShelfID)
            log("Přenos \(operationID.uuidString.prefix(8)) (.copy) potvrzen — odebráno \(op.itemIDs.count) položek")

        case .moveReported:
            op.kind = .externalMove
            var confirmedIDs: [UUID] = []
            var inProgressIDs: [UUID] = []

            let sourceItemsByID = Dictionary(
                uniqueKeysWithValues: (shelf(id: op.sourceShelfID)?.items ?? []).map { ($0.id, $0) }
            )

            for id in op.itemIDs {
                guard let item = sourceItemsByID[id] else { continue }
                let stillAtOriginalPath = FileManager.default.fileExists(atPath: item.lastKnownURL.path)
                if !stillAtOriginalPath {
                    op.itemStatuses[id] = .confirmed
                    confirmedIDs.append(id)
                } else {
                    op.itemStatuses[id] = .inProgress
                    inProgressIDs.append(id)
                }
            }

            activeTransfers[operationID] = op
            if !confirmedIDs.isEmpty {
                removeItems(ids: confirmedIDs, from: op.sourceShelfID)
            }

            if !inProgressIDs.isEmpty {
                log("Přenos \(operationID.uuidString.prefix(8)) (.move): \(confirmedIDs.count) potvrzeno, \(inProgressIDs.count) čeká na dokončení ve Finderu")
                observePendingMove(operationID: operationID, itemIDs: inProgressIDs)
            } else {
                log("Přenos \(operationID.uuidString.prefix(8)) (.move) potvrzen — odebráno \(confirmedIDs.count) položek")
            }
        }
    }

    /// Resolves an unverifiable transfer after explicit user choice.
    public func resolveUnverifiableTransfer(operationID: UUID, removeRemainingItems: Bool) {
        guard let idx = unverifiableTransfers.firstIndex(where: { $0.id == operationID }) else { return }
        let op = unverifiableTransfers.remove(at: idx)
        if removeRemainingItems {
            let remainingIDs = Array(op.itemStatuses.keys)
            removeItems(ids: remainingIDs, from: op.sourceShelfID)
            log("Uživatel potvrdil odebrání \(remainingIDs.count) neověřených položek")
        } else {
            log("Uživatel ponechal neověřené položky na poličce")
        }
    }

    /// Re-checks items marked `.inProgress` for an external `.move` operation.
    /// Returns `true` if all items have been resolved (confirmed and removed).
    @discardableResult
    public func recheckPendingMove(operationID: UUID, finalizeUnresolvedAsUnverifiable: Bool = false) -> Bool {
        guard var op = activeTransfers[operationID] else { return true }
        let inProgressIDs = op.itemStatuses.filter { $0.value == .inProgress }.map(\.key)
        guard !inProgressIDs.isEmpty else { return true }

        let sourceItemsByID = Dictionary(
            uniqueKeysWithValues: (shelf(id: op.sourceShelfID)?.items ?? []).map { ($0.id, $0) }
        )

        var newlyConfirmed: [UUID] = []
        var stillPending: [UUID] = []

        for id in inProgressIDs {
            guard let item = sourceItemsByID[id] else {
                op.itemStatuses[id] = .confirmed
                continue
            }
            if !FileManager.default.fileExists(atPath: item.lastKnownURL.path) {
                op.itemStatuses[id] = .confirmed
                newlyConfirmed.append(id)
            } else if finalizeUnresolvedAsUnverifiable {
                op.itemStatuses[id] = .unverifiable
                stillPending.append(id)
            } else {
                stillPending.append(id)
            }
        }

        if !newlyConfirmed.isEmpty {
            removeItems(ids: newlyConfirmed, from: op.sourceShelfID)
            log("Přenos \(operationID.uuidString.prefix(8)) (.move): potvrzeno \(newlyConfirmed.count) položek po dokončení ve Finderu")
        }

        activeTransfers[operationID] = op

        if finalizeUnresolvedAsUnverifiable && !stillPending.isEmpty {
            var pendingOp = op
            pendingOp.itemStatuses = op.itemStatuses.filter { stillPending.contains($0.key) }
            unverifiableTransfers.append(pendingOp)
            log("Přenos \(operationID.uuidString.prefix(8)) (.move): \(stillPending.count) položek stále na původním místě — nelze ověřit")
            return true
        }

        return stillPending.isEmpty
    }

    private func observePendingMove(operationID: UUID, itemIDs: [UUID]) {
        Task { [weak self] in
            let delaysMs: [UInt64] = [120, 250, 500, 1000]
            for (index, delay) in delaysMs.enumerated() {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self else { return }
                let isLast = index == delaysMs.count - 1
                let done = self.recheckPendingMove(
                    operationID: operationID,
                    finalizeUnresolvedAsUnverifiable: isLast
                )
                if done { return }
            }
        }
    }

    /// Completes an internal drag-and-drop between two Odkladiste shelves.
    @discardableResult
    public func completeInternalTransfer(
        payload: InternalDragPayload,
        to targetShelfID: UUID,
        isCopy: Bool
    ) -> Bool {
        guard var op = activeTransfers[payload.operationID], !op.isFinalized else {
            return false
        }
        guard payload.sourceShelfID != targetShelfID,
              let sourceShelf = shelf(id: payload.sourceShelfID),
              let targetIdx = shelfIndex(targetShelfID) else {
            return false
        }

        let requestedSet = Set(payload.itemIDs)
        let sourceItems = sourceShelf.items.filter { requestedSet.contains($0.id) }
        guard !sourceItems.isEmpty else { return false }

        recordUndo(label: isCopy ? "Kopírovat mezi poličkami" : "Přesunout mezi poličkami")

        op.isFinalized = true
        op.kind = isCopy ? .internalShelfCopy : .internalShelfMove
        for id in payload.itemIDs {
            op.itemStatuses[id] = .confirmed
        }
        activeTransfers[payload.operationID] = op

        for sourceItem in sourceItems {
            let identity = sourceItem.resourceIdentity ?? bookmarkService.resourceIdentity(for: sourceItem.lastKnownURL)
            if let existing = state.shelves[targetIdx].items.first(where: {
                matchesIdentity($0, identity: identity, url: sourceItem.lastKnownURL)
            }) {
                highlightedItemID = existing.id
            } else {
                let copiedItem = ShelfItem(
                    id: UUID(),
                    kind: sourceItem.kind,
                    bookmarkData: sourceItem.bookmarkData,
                    lastKnownURL: sourceItem.lastKnownURL,
                    displayName: sourceItem.displayName,
                    resourceIdentity: identity,
                    addedAt: Date()
                )
                state.shelves[targetIdx].items.append(copiedItem)
                availabilityByItemID[copiedItem.id] = availabilityByItemID[sourceItem.id] ?? .available
            }
        }

        state.shelves[targetIdx].updatedAt = Date()

        if !isCopy {
            removeItems(ids: sourceItems.map(\.id), from: payload.sourceShelfID, recordUndoStep: false)
        } else {
            scheduleSave()
        }

        log("Interní \(isCopy ? "kopie" : "přesun") \(sourceItems.count) položek -> '\(state.shelves[targetIdx].name)'")
        return true
    }

    // MARK: - Undo / Redo & Explicit Shelf Transfers

    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(AppStateSnapshot(state: state, label: snapshot.label))
        state = snapshot.state
        syncUndoFlags()
        refreshAllAvailability()
        scheduleSave()
        log("Zpět: \(snapshot.label)")
    }

    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(AppStateSnapshot(state: state, label: snapshot.label))
        state = snapshot.state
        syncUndoFlags()
        refreshAllAvailability()
        scheduleSave()
        log("Znovu: \(snapshot.label)")
    }

    private func recordUndo(label: String) {
        undoStack.append(AppStateSnapshot(state: state, label: label))
        if undoStack.count > 30 {
            undoStack.removeFirst(undoStack.count - 30)
        }
        redoStack.removeAll()
        syncUndoFlags()
    }

    private func syncUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// Explicitly copies or moves item references between two shelves (from context menu).
    public func transferItemsBetweenShelves(
        itemIDs: [UUID],
        from sourceShelfID: UUID,
        to targetShelfID: UUID,
        isCopy: Bool
    ) {
        guard sourceShelfID != targetShelfID,
              let sourceShelf = shelf(id: sourceShelfID),
              let targetIdx = shelfIndex(targetShelfID) else {
            return
        }
        let requested = Set(itemIDs)
        let sourceItems = sourceShelf.items.filter { requested.contains($0.id) }
        guard !sourceItems.isEmpty else { return }

        recordUndo(label: isCopy ? "Přidat do jiné poličky" : "Přesunout do poličky")

        for sourceItem in sourceItems {
            let identity = sourceItem.resourceIdentity ?? bookmarkService.resourceIdentity(for: sourceItem.lastKnownURL)
            if let existing = state.shelves[targetIdx].items.first(where: {
                matchesIdentity($0, identity: identity, url: sourceItem.lastKnownURL)
            }) {
                highlightedItemID = existing.id
            } else {
                let copiedItem = ShelfItem(
                    id: UUID(),
                    kind: sourceItem.kind,
                    bookmarkData: sourceItem.bookmarkData,
                    lastKnownURL: sourceItem.lastKnownURL,
                    displayName: sourceItem.displayName,
                    resourceIdentity: identity,
                    addedAt: Date()
                )
                state.shelves[targetIdx].items.append(copiedItem)
                availabilityByItemID[copiedItem.id] = availabilityByItemID[sourceItem.id] ?? .available
            }
        }
        state.shelves[targetIdx].updatedAt = Date()

        if !isCopy {
            removeItems(ids: sourceItems.map(\.id), from: sourceShelfID, recordUndoStep: false)
        } else {
            scheduleSave()
        }
    }

    // MARK: - Persistence

    public func flushPersistence() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try persistence.save(state)
        } catch {
            log("Chyba ukládání stavu: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.flushPersistence()
        }
    }

    // MARK: - Helpers

    public func shelf(id: UUID) -> Shelf? {
        state.shelves.first { $0.id == id }
    }

    private func shelfIndex(_ id: UUID) -> Int? {
        state.shelves.firstIndex { $0.id == id }
    }

    private func createShelfObject(
        name: String,
        color: ShelfColor,
        placement: WindowPlacement? = nil
    ) -> Shelf {
        Shelf(
            name: name,
            colorID: color,
            isPinned: false,
            isVisible: true,
            isAlwaysOnTop: true,
            displayMode: .grid,
            windowPlacement: placement
        )
    }

    private func nextDefaultShelfName(excluding extraNames: [String] = []) -> String {
        let existing = Set(state.shelves.map(\.name)).union(extraNames)
        var n = 1
        while existing.contains("\(defaultShelfPrefix) \(n)") {
            n += 1
        }
        return "\(defaultShelfPrefix) \(n)"
    }

    private func matchesIdentity(_ item: ShelfItem, identity: String, url: URL) -> Bool {
        if let existingIdentity = item.resourceIdentity {
            return existingIdentity == identity
        }
        return item.lastKnownURL.standardizedFileURL.path == url.standardizedFileURL.path
    }

    private func log(_ message: String) {
        diagnostics.append(PrototypeDiagnosticEvent(message: message))
        if diagnostics.count > 100 {
            diagnostics.removeFirst(diagnostics.count - 100)
        }
    }
}

/// Outcome reported by AppKit's `NSDraggingSource.draggingSession(_:endedAt:operation:)`.
public enum ExternalDragOutcome: Sendable, Equatable {
    case cancelled
    case copyConfirmed
    case moveReported
}
