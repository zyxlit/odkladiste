import Testing
import Foundation
@testable import OdkladisteCore

@MainActor
struct OdkladisteCoreTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OdkladisteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTempFile(in baseDir: URL, name: String, subfolder: String? = nil, contents: String = "hello") throws -> URL {
        let dir = subfolder.map { baseDir.appendingPathComponent($0, isDirectory: true) } ?? baseDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    @Test func deduplicationAndCrossShelfSharing() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let persistence = PersistenceService(baseDirectory: tempDir.appendingPathComponent("AppSupport", isDirectory: true))

        let store = ShelfStore(persistence: persistence, bootstrapPrototypeShelvesIfEmpty: false)
        let s1 = store.createShelf(name: "S1")
        let s2 = store.createShelf(name: "S2")

        let fileA = try makeTempFile(in: tempDir, name: "logo.png", subfolder: "FolderA")
        let fileB = try makeTempFile(in: tempDir, name: "logo.png", subfolder: "FolderB")

        let r1 = store.addFileURLs([fileA, fileA, fileB], to: s1.id)
        #expect(r1.addedIDs.count == 2)
        #expect(r1.duplicateIDs.count == 1)
        #expect(store.shelf(id: s1.id)?.items.count == 2)

        let r2 = store.addFileURLs([fileA], to: s2.id)
        #expect(r2.addedIDs.count == 1)
        #expect(store.shelf(id: s2.id)?.items.count == 1)
    }

    @Test func persistenceBackupRecoveryAndCorruptionPreservation() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let persistence = PersistenceService(baseDirectory: tempDir.appendingPathComponent("AppSupport", isDirectory: true))

        var state = AppState()
        let shelf = Shelf(name: "Web", colorID: .green)
        state.shelves = [shelf]
        state.shelfOrder = [shelf.id]

        try persistence.save(state)
        var updated = state
        updated.shelves[0].name = "Web v2"
        try persistence.save(updated)

        let primaryURL = persistence.baseDirectory.appendingPathComponent("state.json")
        try Data("{not valid json".utf8).write(to: primaryURL)

        let loaded = persistence.load()
        #expect(loaded.notice == .restoredFromBackup)
        #expect(loaded.state.shelves.first?.name == "Web")

        let files = try FileManager.default.contentsOfDirectory(atPath: persistence.baseDirectory.path)
        #expect(files.contains { $0.hasPrefix("state.corrupted.") })
    }

    @Test func externalTransferTransactionSafetyAndIdempotency() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let persistence = PersistenceService(baseDirectory: tempDir.appendingPathComponent("AppSupport", isDirectory: true))

        let store = ShelfStore(persistence: persistence, bootstrapPrototypeShelvesIfEmpty: false)
        let shelf = store.createShelf(name: "Work")
        let f1 = try makeTempFile(in: tempDir, name: "a.txt")
        let f2 = try makeTempFile(in: tempDir, name: "b.txt")

        let addResult = store.addFileURLs([f1], to: shelf.id)
        let f1ID = try #require(addResult.addedIDs.first)

        let op = store.beginTransfer(from: shelf.id, itemIDs: [f1ID])
        _ = store.addFileURLs([f2], to: shelf.id)
        #expect(store.shelf(id: shelf.id)?.items.count == 2)

        store.completeExternalTransfer(operationID: op.id, dragOutcome: .copyConfirmed)
        #expect(store.shelf(id: shelf.id)?.items.count == 1)
        #expect(store.shelf(id: shelf.id)?.items.first?.displayName == "b.txt")

        store.completeExternalTransfer(operationID: op.id, dragOutcome: .copyConfirmed)
        #expect(store.shelf(id: shelf.id)?.items.count == 1)
    }

    @Test func externalMoveVerificationHandlesUnverifiableAndConfirmedMoves() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let persistence = PersistenceService(baseDirectory: tempDir.appendingPathComponent("AppSupport", isDirectory: true))

        let store = ShelfStore(persistence: persistence, bootstrapPrototypeShelvesIfEmpty: false)
        let shelf = store.createShelf(name: "MoveTest")
        let f1 = try makeTempFile(in: tempDir, name: "stays.txt")
        let f2 = try makeTempFile(in: tempDir, name: "moved.txt")

        let added = store.addFileURLs([f1, f2], to: shelf.id)
        let op = store.beginTransfer(from: shelf.id, itemIDs: added.addedIDs)

        try FileManager.default.removeItem(at: f2)
        store.completeExternalTransfer(operationID: op.id, dragOutcome: .moveReported)

        // f2 is immediately confirmed & removed; f1 is inProgress (not unverifiable yet)
        #expect(store.shelf(id: shelf.id)?.items.map(\.displayName) == ["stays.txt"])
        #expect(store.unverifiableTransfers.isEmpty)

        // Final recheck when f1 still exists marks it unverifiable
        store.recheckPendingMove(operationID: op.id, finalizeUnresolvedAsUnverifiable: true)
        #expect(store.unverifiableTransfers.count == 1)

        store.resolveUnverifiableTransfer(operationID: op.id, removeRemainingItems: false)
        #expect(store.shelf(id: shelf.id)?.items.count == 1)
        #expect(store.unverifiableTransfers.isEmpty)

        // Now test async move completion: file disappears after endedAt
        let op2 = store.beginTransfer(from: shelf.id, itemIDs: [added.addedIDs[0]])
        store.completeExternalTransfer(operationID: op2.id, dragOutcome: .moveReported)
        #expect(store.shelf(id: shelf.id)?.items.count == 1)
        try FileManager.default.removeItem(at: f1)
        let resolved = store.recheckPendingMove(operationID: op2.id)
        #expect(resolved)
        #expect(store.shelf(id: shelf.id)?.items.isEmpty == true)
        #expect(store.unverifiableTransfers.isEmpty)
    }

    @Test func internalShelfMoveAndCopy() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let persistence = PersistenceService(baseDirectory: tempDir.appendingPathComponent("AppSupport", isDirectory: true))

        let store = ShelfStore(persistence: persistence, bootstrapPrototypeShelvesIfEmpty: false)
        let s1 = store.createShelf(name: "Source")
        let s2 = store.createShelf(name: "Target")
        let f1 = try makeTempFile(in: tempDir, name: "photo.jpg")

        let addResult = store.addFileURLs([f1], to: s1.id)
        let opMove = store.beginTransfer(from: s1.id, itemIDs: addResult.addedIDs)

        let payload = InternalDragPayload(
            operationID: opMove.id,
            sourceShelfID: s1.id,
            itemIDs: addResult.addedIDs
        )
        let ok = store.completeInternalTransfer(payload: payload, to: s2.id, isCopy: false)
        #expect(ok)
        #expect(store.shelf(id: s1.id)?.items.count == 0)
        #expect(store.shelf(id: s2.id)?.items.count == 1)
        #expect(FileManager.default.fileExists(atPath: f1.path))

        store.completeExternalTransfer(operationID: opMove.id, dragOutcome: .moveReported)
        #expect(store.shelf(id: s2.id)?.items.count == 1)
    }

    @Test func displayPlacementClampsDisconnectedMonitor() {
        let disconnectedPlacement = WindowPlacement(
            displayUUID: "EXTERNAL-MONITOR-UUID",
            x: 3000,
            y: 1200,
            width: 320,
            height: 240
        )
        let laptopScreen = ScreenDescriptor(
            displayUUID: "BUILTIN-UUID",
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
        )

        let resolved = DisplayPlacement.resolveFrame(for: disconnectedPlacement, screens: [laptopScreen])
        #expect(laptopScreen.visibleFrame.contains(resolved))
        #expect(resolved.size == CGSize(width: 320, height: 240))
    }

    @Test func undoRedoForEmptyAndShelfTransfers() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let persistence = PersistenceService(baseDirectory: tempDir.appendingPathComponent("AppSupport", isDirectory: true))

        let store = ShelfStore(persistence: persistence, bootstrapPrototypeShelvesIfEmpty: false)
        let s1 = store.createShelf(name: "S1")
        let s2 = store.createShelf(name: "S2")
        let f1 = try makeTempFile(in: tempDir, name: "doc.pdf")

        let addResult = store.addFileURLs([f1], to: s1.id)
        #expect(store.shelf(id: s1.id)?.items.count == 1)

        // Move to S2 via explicit menu transfer, then Undo
        store.transferItemsBetweenShelves(itemIDs: addResult.addedIDs, from: s1.id, to: s2.id, isCopy: false)
        #expect(store.shelf(id: s1.id)?.items.count == 0)
        #expect(store.shelf(id: s2.id)?.items.count == 1)

        store.undo()
        #expect(store.shelf(id: s1.id)?.items.count == 1)
        #expect(store.shelf(id: s2.id)?.items.count == 0)

        // Empty S1, then Undo
        store.emptyShelf(id: s1.id)
        #expect(store.shelf(id: s1.id)?.items.isEmpty == true)

        store.undo()
        #expect(store.shelf(id: s1.id)?.items.count == 1)
        #expect(FileManager.default.fileExists(atPath: f1.path))
    }
}
