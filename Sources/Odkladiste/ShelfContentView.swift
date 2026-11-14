import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OdkladisteCore

extension Notification.Name {
    static let shelfDropHighlightChanged = Notification.Name("OdkladisteShelfDropHighlightChanged")
}

/// AppKit container view handling `NSDraggingDestination` for both internal shelf transfers and Finder file URLs.
final class ShelfDropZoneNSView: NSView {
    private let shelfID: UUID
    private let store: ShelfStore
    private static let internalType = NSPasteboard.PasteboardType(InternalDragPayload.pasteboardTypeIdentifier)

    init(shelfID: UUID, store: ShelfStore) {
        self.shelfID = shelfID
        self.store = store
        super.init(frame: .zero)
        registerForDraggedTypes([Self.internalType, .fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = resolveOperation(for: sender)
        postHighlight(op != [])
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        resolveOperation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        postHighlight(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        postHighlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        postHighlight(false)
        let pb = sender.draggingPasteboard

        // 1. Prefer internal shelf-to-shelf payload
        if let data = pb.data(forType: Self.internalType),
           let payload = try? JSONDecoder().decode(InternalDragPayload.self, from: data) {
            if payload.sourceShelfID == shelfID {
                return false
            }
            let isCopy = NSEvent.modifierFlags.contains(.option)
            return store.completeInternalTransfer(payload: payload, to: shelfID, isCopy: isCopy)
        }

        // 2. External file URLs from Finder / other apps
        let urls = extractFileURLs(from: pb)
        guard !urls.isEmpty else { return false }
        let result = store.addFileURLs(urls, to: shelfID)
        return !result.addedIDs.isEmpty || !result.duplicateIDs.isEmpty
    }

    private func resolveOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if let data = pb.data(forType: Self.internalType),
           let payload = try? JSONDecoder().decode(InternalDragPayload.self, from: data) {
            guard payload.sourceShelfID != shelfID else { return [] }
            return NSEvent.modifierFlags.contains(.option) ? .copy : .move
        }

        let urls = extractFileURLs(from: pb)
        return urls.isEmpty ? [] : .copy
    }

    private func extractFileURLs(from pb: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return objects.filter { $0.isFileURL }
    }

    private func postHighlight(_ isHighlighted: Bool) {
        NotificationCenter.default.post(
            name: .shelfDropHighlightChanged,
            object: nil,
            userInfo: ["shelfID": shelfID, "highlighted": isHighlighted]
        )
    }
}

/// AppKit drag source view initiating `NSDraggingSession` with both internal UTI and `fileURL`,
/// and forwarding non-drag clicks/double-clicks for selection and opening.
final class ShelfItemDragSourceNSView: NSView, NSDraggingSource {
    var shelfID: UUID
    var store: ShelfStore
    var itemProvider: () -> [ShelfItem]
    var onClick: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var activeOperationID: UUID?
    private var mouseDownEvent: NSEvent?

    init(
        shelfID: UUID,
        store: ShelfStore,
        itemProvider: @escaping () -> [ShelfItem],
        onClick: ((NSEvent) -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil
    ) {
        self.shelfID = shelfID
        self.store = store
        self.itemProvider = itemProvider
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?(event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - startEvent.locationInWindow.x
        let dy = event.locationInWindow.y - startEvent.locationInWindow.y
        guard hypot(dx, dy) >= 3 else { return }

        let items = itemProvider().filter { FileManager.default.fileExists(atPath: $0.lastKnownURL.path) }
        guard !items.isEmpty else { return }
        mouseDownEvent = nil

        let operation = store.beginTransfer(from: shelfID, itemIDs: items.map(\.id))
        activeOperationID = operation.id

        let payload = InternalDragPayload(
            operationID: operation.id,
            sourceShelfID: shelfID,
            itemIDs: items.map(\.id)
        )
        let payloadData = try? JSONEncoder().encode(payload)
        let internalType = NSPasteboard.PasteboardType(InternalDragPayload.pasteboardTypeIdentifier)

        var draggingItems: [NSDraggingItem] = []
        for (index, item) in items.enumerated() {
            let pbItem = NSPasteboardItem()
            if index == 0, let payloadData {
                pbItem.setData(payloadData, forType: internalType)
            }
            pbItem.setString(item.lastKnownURL.absoluteString, forType: .fileURL)

            let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
            let icon = NSWorkspace.shared.icon(forFile: item.lastKnownURL.path)
            icon.size = NSSize(width: 32, height: 32)
            let frame = NSRect(x: 0, y: CGFloat(index) * 4, width: 32, height: 32)
            dragItem.setDraggingFrame(frame, contents: icon)
            draggingItems.append(dragItem)
        }

        beginDraggingSession(with: draggingItems, event: startEvent, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return [.copy, .move]
        case .outsideApplication:
            return [.copy, .move]
        @unknown default:
            return [.copy]
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        guard let opID = activeOperationID else { return }
        activeOperationID = nil

        let outcome: ExternalDragOutcome
        if operation == [] {
            outcome = .cancelled
        } else if operation.contains(.move) {
            outcome = .moveReported
        } else {
            outcome = .copyConfirmed
        }

        store.completeExternalTransfer(operationID: opID, dragOutcome: outcome)
    }
}

struct DragHandleRepresentable: NSViewRepresentable {
    let shelfID: UUID
    let store: ShelfStore
    let items: () -> [ShelfItem]
    var onClick: ((NSEvent) -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> ShelfItemDragSourceNSView {
        ShelfItemDragSourceNSView(
            shelfID: shelfID,
            store: store,
            itemProvider: items,
            onClick: onClick,
            onDoubleClick: onDoubleClick
        )
    }

    func updateNSView(_ nsView: ShelfItemDragSourceNSView, context: Context) {
        nsView.shelfID = shelfID
        nsView.store = store
        nsView.itemProvider = items
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
    }
}

final class WindowDragAreaNSView: NSView {
    var onDoubleClick: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }
}

struct WindowDragAreaRepresentable: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> WindowDragAreaNSView {
        let view = WindowDragAreaNSView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: WindowDragAreaNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

final class ResizeCornerGripNSView: NSView {
    private var initialMouseLocation: NSPoint = .zero
    private var initialFrame: NSRect = .zero

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        if #available(macOS 15.0, *) {
            NSCursor.frameResize(position: .bottomRight, directions: .all).set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialMouseLocation = NSEvent.mouseLocation
        initialFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - initialMouseLocation.x
        let dy = current.y - initialMouseLocation.y

        let minSize = window.minSize
        let newWidth = max(minSize.width, initialFrame.width + dx)
        let newHeight = max(minSize.height, initialFrame.height - dy)
        let newY = initialFrame.maxY - newHeight

        let newFrame = NSRect(x: initialFrame.origin.x, y: newY, width: newWidth, height: newHeight)
        window.setFrame(newFrame, display: true)
    }
}

struct ResizeCornerGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCornerGripNSView {
        ResizeCornerGripNSView()
    }

    func updateNSView(_ nsView: ResizeCornerGripNSView, context: Context) {}
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum ThumbnailSizeOption: String, CaseIterable {
    case small
    case medium
    case large

    @MainActor
    func localizedTitle(l10n: L10n) -> String {
        switch self {
        case .small: return l10n.t("Malé", "Small")
        case .medium: return l10n.t("Střední", "Medium")
        case .large: return l10n.t("Velké", "Large")
        }
    }

    var gridIconSize: CGFloat {
        switch self {
        case .small: return 30
        case .medium: return 42
        case .large: return 58
        }
    }

    var gridMinColumnWidth: CGFloat {
        switch self {
        case .small: return 62
        case .medium: return 78
        case .large: return 98
        }
    }

    var listIconSize: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 22
        case .large: return 28
        }
    }
}

struct ShelfPanelRootView: View {
    let shelfID: UUID
    @ObservedObject var store: ShelfStore
    @ObservedObject private var l10n = L10n.shared
    let onRequestRenameFocus: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("odkladiste.thumbnailSize") private var thumbnailSizeRaw: String = ThumbnailSizeOption.medium.rawValue
    @State private var isDropHighlighted = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isSearching = false
    @State private var searchQuery = ""
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var showDiagnostics = false
    @State private var confirmEmpty = false
    @State private var confirmDelete = false
    @FocusState private var renameFocused: Bool
    @FocusState private var searchFocused: Bool

    private var thumbnailSize: ThumbnailSizeOption {
        ThumbnailSizeOption(rawValue: thumbnailSizeRaw) ?? .medium
    }

    private var shelf: Shelf? {
        store.shelf(id: shelfID)
    }

    private var duplicateNamesInShelf: Set<String> {
        guard let shelf else { return [] }
        var counts: [String: Int] = [:]
        for item in shelf.items {
            counts[item.displayName, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    private var pendingUnverifiableForShelf: [TransferOperation] {
        store.unverifiableTransfers.filter { $0.sourceShelfID == shelfID }
    }

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectBackground()
            }

            if let shelf {
                let visibleItems = filteredItems(in: shelf)
                VStack(spacing: 0) {
                    headerView(shelf)
                    Divider().opacity(0.35)

                    if isSearching {
                        searchBarView
                        Divider().opacity(0.3)
                    }

                    if !pendingUnverifiableForShelf.isEmpty {
                        unverifiableBanner(pendingUnverifiableForShelf[0])
                        Divider().opacity(0.3)
                    }

                    if shelf.items.isEmpty {
                        emptyStateView
                            .contextMenu {
                                shelfActionsMenuContent(shelf)
                            }
                    } else if visibleItems.isEmpty {
                        Text(l10n.t("Žádné položky neodpovídají hledání", "No items match your filter"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if shelf.displayMode == .grid {
                        itemsGridView(shelf, items: visibleItems)
                    } else {
                        itemsListView(shelf, items: visibleItems)
                    }

                    if showDiagnostics {
                        Divider().opacity(0.35)
                        diagnosticsView
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(90))
                        ResizeCornerGrip()
                    }
                    .frame(width: 16, height: 16)
                    .padding(3)
                    .help("Změnit velikost poličky")
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropHighlighted ? Color.accentColor : Color.primary.opacity(0.14),
                    lineWidth: isDropHighlighted ? 2.5 : 1
                )
        )
        .onReceive(NotificationCenter.default.publisher(for: .shelfDropHighlightChanged)) { notif in
            guard let id = notif.userInfo?["shelfID"] as? UUID,
                  id == shelfID,
                  let highlighted = notif.userInfo?["highlighted"] as? Bool else { return }
            isDropHighlighted = highlighted
        }
        .onReceive(NotificationCenter.default.publisher(for: .shelfKeyCommand)) { notif in
            guard let id = notif.userInfo?["shelfID"] as? UUID,
                  id == shelfID,
                  let command = notif.userInfo?["command"] as? ShelfKeyCommand else { return }
            handleKeyCommand(command)
        }
        .confirmationDialog(
            l10n.t("Vyprázdnit poličku?", "Empty Shelf?"),
            isPresented: $confirmEmpty,
            titleVisibility: .visible
        ) {
            Button(l10n.t("Vyprázdnit", "Empty"), role: .destructive) {
                store.emptyShelf(id: shelfID)
            }
            Button(l10n.t("Zrušit", "Cancel"), role: .cancel) {}
        } message: {
            Text(l10n.t(
                "Odeberou se pouze odkazy v poličce. Původní soubory na disku zůstanou.",
                "Only shelf references will be removed. Original files on disk remain untouched."
            ))
        }
        .confirmationDialog(
            l10n.t("Odstranit poličku?", "Delete Shelf?"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(l10n.t("Odstranit poličku", "Delete Shelf"), role: .destructive) {
                store.deleteShelf(id: shelfID)
            }
            Button(l10n.t("Zrušit", "Cancel"), role: .cancel) {}
        } message: {
            Text(l10n.t(
                "Smaže se polička a její odkazy. Původní soubory na disku zůstanou.",
                "The shelf and its references will be deleted. Original files on disk remain untouched."
            ))
        }
    }

    private func headerView(_ shelf: Shelf) -> some View {
        ZStack {
            WindowDragAreaRepresentable {
                draftName = shelf.name
                isRenaming = true
                onRequestRenameFocus()
                renameFocused = true
            }

            HStack(spacing: 8) {
                Button {
                    store.setShelfVisible(id: shelf.id, isVisible: false)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Skrýt poličku")
                .accessibilityLabel("Skrýt poličku")

                Circle()
                    .fill(ShelfColorPalette.color(for: shelf))
                    .frame(width: 9, height: 9)
                    .allowsHitTesting(false)

                if isRenaming {
                    TextField("Název poličky", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($renameFocused)
                        .onSubmit {
                            store.renameShelf(id: shelf.id, to: draftName)
                            isRenaming = false
                        }
                        .onExitCommand {
                            isRenaming = false
                        }
                } else {
                    Text(shelf.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                Spacer()
                    .allowsHitTesting(false)

                Text("\(shelf.items.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .allowsHitTesting(false)

                dragAllHandle(shelf)

                Menu {
                    shelfActionsMenuContent(shelf)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: 36)
        .background(ShelfColorPalette.color(for: shelf).opacity(0.14))
        .contextMenu {
            shelfActionsMenuContent(shelf)
        }
    }

    @ViewBuilder
    private func shelfActionsMenuContent(_ shelf: Shelf) -> some View {
        Button(l10n.t("Přejmenovat", "Rename")) {
            draftName = shelf.name
            isRenaming = true
            onRequestRenameFocus()
            renameFocused = true
        }

        Menu(l10n.t("Barva", "Color")) {
            ForEach(ShelfColor.allCases, id: \.self) { color in
                Toggle(isOn: Binding(
                    get: { shelf.customColorHex == nil && shelf.colorID == color },
                    set: { isSelected in
                        if isSelected {
                            store.setShelfColor(id: shelf.id, color: color)
                        }
                    }
                )) {
                    Text(l10n.colorName(color))
                }
            }
            Divider()
            if let customHex = shelf.customColorHex {
                Toggle(isOn: .constant(true)) {
                    Text("\(l10n.t("Vlastní", "Custom")): \(customHex)")
                }
            }
            Button(l10n.t("Barevné kolo a kapátko…", "Color Wheel & Eyedropper…")) {
                ShelfColorPanelCoordinator.shared.open(for: shelf) { hex in
                    _ = store.setShelfCustomColorHex(id: shelf.id, hex: hex)
                }
            }
            Button(shelf.customColorHex != nil
                   ? l10n.t("Upravit hex kód…", "Edit Hex Code…")
                   : l10n.t("Vlastní hex…", "Custom Hex…")) {
                promptForCustomHex(shelf: shelf)
            }
        }

        Toggle(l10n.t("Připnout do nabídky", "Pin to Menu"), isOn: Binding(
            get: { shelf.isPinned },
            set: { store.setShelfPinned(id: shelf.id, isPinned: $0) }
        ))

        Toggle(l10n.t("Vždy navrchu", "Always on Top"), isOn: Binding(
            get: { shelf.isAlwaysOnTop },
            set: { store.setShelfAlwaysOnTop(id: shelf.id, isAlwaysOnTop: $0) }
        ))

        Button(shelf.displayMode == .grid
               ? l10n.t("Zobrazit jako seznam", "Show as List")
               : l10n.t("Zobrazit jako mřížku", "Show as Grid")) {
            store.setDisplayMode(
                id: shelf.id,
                mode: shelf.displayMode == .grid ? .list : .grid
            )
        }

        Menu(l10n.t("Velikost náhledů", "Thumbnail Size")) {
            ForEach(ThumbnailSizeOption.allCases, id: \.self) { option in
                Button {
                    thumbnailSizeRaw = option.rawValue
                } label: {
                    if thumbnailSize == option {
                        Label(option.localizedTitle(l10n: l10n), systemImage: "checkmark")
                    } else {
                        Text(option.localizedTitle(l10n: l10n))
                    }
                }
            }
        }

        Toggle(l10n.t("Diagnostika", "Diagnostics"), isOn: $showDiagnostics)

        Divider()

        Button(l10n.t("Vyprázdnit", "Empty"), role: .destructive) {
            if shelf.items.isEmpty {
                store.emptyShelf(id: shelf.id)
            } else {
                confirmEmpty = true
            }
        }
        .disabled(shelf.items.isEmpty)

        Button(l10n.t("Skrýt", "Hide")) {
            store.setShelfVisible(id: shelf.id, isVisible: false)
        }

        Button(l10n.t("Odstranit poličku", "Delete Shelf"), role: .destructive) {
            if shelf.items.isEmpty {
                store.deleteShelf(id: shelf.id)
            } else {
                confirmDelete = true
            }
        }
    }

    private func dragAllHandle(_ shelf: Shelf) -> some View {
        let hasItems = !shelf.items.isEmpty
        let accent = ShelfColorPalette.color(for: shelf)

        return ZStack {
            HStack(spacing: 4) {
                Image(systemName: hasItems ? "tray.and.arrow.up.fill" : "tray.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text(l10n.t("Vše", "All"))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(hasItems ? Color.white : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(hasItems ? accent.opacity(0.92) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .strokeBorder(hasItems ? Color.white.opacity(0.20) : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .opacity(hasItems ? 1.0 : 0.45)

            if hasItems {
                DragHandleRepresentable(shelfID: shelf.id, store: store, items: { shelf.items })
            }
        }
        .fixedSize()
        .help(hasItems
              ? l10n.t("Přetáhnout všechny položky z poličky (\(shelf.items.count))", "Drag all items from shelf (\(shelf.items.count))")
              : l10n.t("Polička je prázdná", "Shelf is empty"))
        .accessibilityLabel(hasItems
                            ? l10n.t("Přetáhnout vše z poličky", "Drag all from shelf")
                            : l10n.t("Přetáhnout vše (prázdná polička)", "Drag all (empty shelf)"))
    }

    private func unverifiableBanner(_ op: TransferOperation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text(l10n.t("Předání nelze ověřit (\(op.itemStatuses.count))", "Transfer unverifiable (\(op.itemStatuses.count))"))
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Button(l10n.t("Odebrat", "Remove")) {
                store.resolveUnverifiableTransfer(operationID: op.id, removeRemainingItems: true)
            }
            .controlSize(.mini)
            Button(l10n.t("Ponechat", "Keep")) {
                store.resolveUnverifiableTransfer(operationID: op.id, removeRemainingItems: false)
            }
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.14))
    }

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(l10n.t("Přetáhni sem soubory", "Drop files here"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(l10n.t("Nová polička: ⌃⌥N  •  Skrýt vše: ⌃⌥O", "New shelf: ⌃⌥N  •  Hide all: ⌃⌥O"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var searchBarView: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Filtrovat v poličce…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onExitCommand {
                    searchQuery = ""
                    isSearching = false
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
    }

    private func filteredItems(in shelf: Shelf) -> [ShelfItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return shelf.items }
        return shelf.items.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.lastKnownURL.path.localizedCaseInsensitiveContains(query)
        }
    }

    private func handleKeyCommand(_ command: ShelfKeyCommand) {
        guard let shelf else { return }
        let visible = filteredItems(in: shelf)

        switch command {
        case .selectAll:
            selectedItemIDs = Set(visible.map(\.id))
            selectionAnchorID = visible.first?.id
        case .toggleSearch:
            isSearching.toggle()
            if isSearching {
                onRequestRenameFocus()
                searchFocused = true
            } else {
                searchQuery = ""
            }
        case .quickLook:
            let targets = visible.filter { selectedItemIDs.contains($0.id) }
            let urls = (targets.isEmpty ? visible.prefix(1).map { $0 } : targets).map(\.lastKnownURL)
            QuickLookService.shared.togglePreview(for: urls)
        case .deleteSelected:
            let ids = Array(selectedItemIDs)
            if !ids.isEmpty {
                store.removeItems(ids: ids, from: shelf.id)
                selectedItemIDs.subtract(ids)
            }
        case .undo:
            store.undo()
        case .redo:
            store.redo()
        case .escape:
            if isSearching {
                searchQuery = ""
                isSearching = false
            } else if !selectedItemIDs.isEmpty {
                selectedItemIDs.removeAll()
                selectionAnchorID = nil
            }
        }
    }

    private func handleItemClick(_ item: ShelfItem, event: NSEvent, in items: [ShelfItem]) {
        onRequestRenameFocus()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
            selectionAnchorID = item.id
        } else if flags.contains(.shift),
                  let anchorID = selectionAnchorID,
                  let startIdx = items.firstIndex(where: { $0.id == anchorID }),
                  let endIdx = items.firstIndex(where: { $0.id == item.id }) {
            let range = min(startIdx, endIdx)...max(startIdx, endIdx)
            for idx in range {
                selectedItemIDs.insert(items[idx].id)
            }
        } else {
            selectedItemIDs = [item.id]
            selectionAnchorID = item.id
        }
    }

    private func itemsGridView(_ shelf: Shelf, items: [ShelfItem]) -> some View {
        let minCol = thumbnailSize.gridMinColumnWidth
        let columns = [GridItem(.adaptive(minimum: minCol, maximum: minCol + 18), spacing: 8)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    itemTile(item, in: shelf, visibleItems: items)
                }
            }
            .padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItemIDs.removeAll()
        }
    }

    private func itemTile(_ item: ShelfItem, in shelf: Shelf, visibleItems: [ShelfItem]) -> some View {
        let availability = store.availabilityByItemID[item.id] ?? .available
        let showParent = duplicateNamesInShelf.contains(item.displayName)
        let isSelected = selectedItemIDs.contains(item.id)
        let isHighlighted = store.highlightedItemID == item.id

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    FileThumbnailView(url: item.lastKnownURL, size: thumbnailSize.gridIconSize)
                        .opacity(availability == .available ? 1.0 : 0.5)

                    if availability != .available {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .background(Circle().fill(.background))
                    }
                }

                Text(item.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(availability == .available ? .primary : .secondary)

                if showParent {
                    Text("…/\(item.parentFolderName)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected ? Color.accentColor.opacity(0.28) :
                        isHighlighted ? Color.accentColor.opacity(0.18) :
                        Color.primary.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )

            DragHandleRepresentable(
                shelfID: shelf.id,
                store: store,
                items: {
                    if selectedItemIDs.contains(item.id) {
                        return visibleItems.filter { selectedItemIDs.contains($0.id) }
                    }
                    return [item]
                },
                onClick: { event in
                    handleItemClick(item, event: event, in: visibleItems)
                },
                onDoubleClick: {
                    NSWorkspace.shared.open(item.lastKnownURL)
                }
            )

            Button {
                store.removeItems(ids: [item.id], from: shelf.id)
                selectedItemIDs.remove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(4)
            .help("Odebrat odkaz z poličky")
            .accessibilityLabel("Odebrat \(item.displayName)")
        }
        .help(item.lastKnownURL.path)
        .contextMenu {
            itemContextMenu(item, in: shelf, visibleItems: visibleItems)
        }
    }

    private func itemsListView(_ shelf: Shelf, items: [ShelfItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(items) { item in
                    itemRow(item, in: shelf, visibleItems: items)
                }
            }
            .padding(8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItemIDs.removeAll()
        }
    }

    private func itemRow(_ item: ShelfItem, in shelf: Shelf, visibleItems: [ShelfItem]) -> some View {
        let availability = store.availabilityByItemID[item.id] ?? .available
        let showParent = duplicateNamesInShelf.contains(item.displayName)
        let isSelected = selectedItemIDs.contains(item.id)
        let isHighlighted = store.highlightedItemID == item.id

        return ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                FileThumbnailView(url: item.lastKnownURL, size: thumbnailSize.listIconSize)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(availability == .available ? .primary : .secondary)

                    if showParent {
                        Text("…/\(item.parentFolderName)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if availability != .available {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help("Soubor není dostupný")
                }

                Button {
                    store.removeItems(ids: [item.id], from: shelf.id)
                    selectedItemIDs.remove(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Odebrat odkaz z poličky")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected ? Color.accentColor.opacity(0.28) :
                        isHighlighted ? Color.accentColor.opacity(0.18) :
                        Color.primary.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )

            // Drag handle over the item content (leaving the remove button clickable on the right)
            DragHandleRepresentable(
                shelfID: shelf.id,
                store: store,
                items: {
                    if selectedItemIDs.contains(item.id) {
                        return visibleItems.filter { selectedItemIDs.contains($0.id) }
                    }
                    return [item]
                },
                onClick: { event in
                    handleItemClick(item, event: event, in: visibleItems)
                },
                onDoubleClick: {
                    NSWorkspace.shared.open(item.lastKnownURL)
                }
            )
            .padding(.trailing, 26)
        }
        .help(item.lastKnownURL.path)
        .contextMenu {
            itemContextMenu(item, in: shelf, visibleItems: visibleItems)
        }
    }

    @ViewBuilder
    private func itemContextMenu(_ item: ShelfItem, in shelf: Shelf, visibleItems: [ShelfItem]) -> some View {
        let targetItems: [ShelfItem] = selectedItemIDs.contains(item.id)
            ? visibleItems.filter { selectedItemIDs.contains($0.id) }
            : [item]
        let targetIDs = targetItems.map(\.id)
        let otherShelves = store.orderedShelves.filter { $0.id != shelf.id }

        Button(l10n.t("Otevřít", "Open")) {
            for t in targetItems {
                NSWorkspace.shared.open(t.lastKnownURL)
            }
        }
        Button(l10n.t("Rychlý náhled", "Quick Look")) {
            QuickLookService.shared.togglePreview(for: targetItems.map(\.lastKnownURL))
        }
        Button(l10n.t("Ukázat ve Finderu", "Show in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting(targetItems.map(\.lastKnownURL))
        }
        Button(l10n.t("Kopírovat cestu", "Copy Path")) {
            let paths = targetItems.map(\.lastKnownURL.path).joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
        }

        if !otherShelves.isEmpty {
            Divider()
            Menu(l10n.t("Přidat do jiné poličky", "Add to Another Shelf")) {
                ForEach(otherShelves) { dest in
                    Button(dest.name) {
                        store.transferItemsBetweenShelves(itemIDs: targetIDs, from: shelf.id, to: dest.id, isCopy: true)
                    }
                }
            }
            Menu(l10n.t("Přesunout do poličky", "Move to Shelf")) {
                ForEach(otherShelves) { dest in
                    Button(dest.name) {
                        store.transferItemsBetweenShelves(itemIDs: targetIDs, from: shelf.id, to: dest.id, isCopy: false)
                        selectedItemIDs.subtract(targetIDs)
                    }
                }
            }
        }

        Divider()
        Button(l10n.t("Odebrat z poličky", "Remove from Shelf"), role: .destructive) {
            store.removeItems(ids: targetIDs, from: shelf.id)
            selectedItemIDs.subtract(targetIDs)
        }
    }

    private var diagnosticsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(store.diagnostics.suffix(8).reversed()) { event in
                    Text(event.message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(6)
        }
        .frame(height: 82)
        .background(Color.black.opacity(0.12))
    }

    private func promptForCustomHex(shelf: Shelf) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = l10n.t("Vlastní barva poličky", "Custom Shelf Color")
        alert.informativeText = l10n.t("Zadej 6místný hex kód (např. #FF6B35):", "Enter a 6-digit hex code (e.g. #FF6B35):")
        alert.addButton(withTitle: l10n.t("Použít", "Apply"))
        alert.addButton(withTitle: l10n.t("Zrušit", "Cancel"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        input.stringValue = shelf.customColorHex ?? "#"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        if alert.runModal() == .alertFirstButtonReturn {
            _ = store.setShelfCustomColorHex(id: shelf.id, hex: input.stringValue)
        }
    }
}
