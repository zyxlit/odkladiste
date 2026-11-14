import AppKit
import SwiftUI
import OdkladisteCore

/// Interactive menu bar popover that stays open across shelf edits (color, pin, rename, show/hide).
struct MenuBarPopoverView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject private var l10n = L10n.shared
    let onNewShelf: () -> Void
    let onSelectShelf: (UUID) -> Void
    let onToggleShelfVisibility: (UUID) -> Void
    let onToggleAllShelves: () -> Void
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void

    @State private var expandedShelfID: UUID?
    @State private var renamingShelfID: UUID?
    @State private var draftName: String = ""
    @State private var hexEditingShelfID: UUID?
    @State private var hexInput: String = ""
    @State private var hexError: Bool = false
    @State private var searchText: String = ""
    @State private var shelfPendingEmpty: Shelf?
    @State private var shelfPendingDelete: Shelf?

    private var filteredShelves: [Shelf] {
        let ordered = store.orderedShelves
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ordered }
        return ordered.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var pinnedShelves: [Shelf] {
        filteredShelves.filter(\.isPinned)
    }

    private var otherShelves: [Shelf] {
        filteredShelves.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top action: New Shelf
            Button(action: onNewShelf) {
                HStack {
                    Image(systemName: "plus.square.on.square")
                        .foregroundStyle(Color.accentColor)
                    Text(l10n.t("Nová polička", "New Shelf"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("⌃⌥N")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if store.state.shelves.count > 5 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField(l10n.t("Hledat poličku…", "Search shelves…"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !pinnedShelves.isEmpty {
                        sectionHeader(l10n.t("Připnuté", "Pinned"))
                        ForEach(pinnedShelves) { shelf in
                            shelfRow(shelf)
                        }
                        if !otherShelves.isEmpty {
                            Divider().padding(.vertical, 4)
                        }
                    }

                    if !otherShelves.isEmpty {
                        if !pinnedShelves.isEmpty {
                            sectionHeader(l10n.t("Ostatní", "Other"))
                        }
                        ForEach(otherShelves) { shelf in
                            shelfRow(shelf)
                        }
                    }

                    if filteredShelves.isEmpty {
                        Text(l10n.t("Žádné poličky", "No shelves"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: min(max(CGFloat(filteredShelves.count) * 34 + (expandedShelfID != nil ? 76 : 0) + 20, 64), 360))

            Divider()

            // Footer actions
            VStack(spacing: 2) {
                if !store.state.shelves.isEmpty {
                    let anyVisible = store.state.shelves.contains { $0.isVisible }
                    footerButton(
                        title: anyVisible ? l10n.t("Skrýt všechny", "Hide All") : l10n.t("Zobrazit všechny", "Show All"),
                        shortcut: "⌃⌥O",
                        action: onToggleAllShelves
                    )
                }
                footerButton(title: l10n.t("Nastavení…", "Settings…"), shortcut: "⌘,", action: onSettings)
                footerButton(title: l10n.t("O aplikaci Odkladiště", "About Odkladiště"), shortcut: nil, action: onAbout)
                footerButton(title: l10n.t("Ukončit Odkladiště", "Quit Odkladiště"), shortcut: "⌘Q", action: onQuit)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 316)
        .confirmationDialog(
            l10n.t("Vyprázdnit poličku „\(shelfPendingEmpty?.name ?? "")“?", "Empty shelf “\(shelfPendingEmpty?.name ?? "")”?"),
            isPresented: Binding(
                get: { shelfPendingEmpty != nil },
                set: { if !$0 { shelfPendingEmpty = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(l10n.t("Vyprázdnit", "Empty"), role: .destructive) {
                if let shelf = shelfPendingEmpty {
                    store.emptyShelf(id: shelf.id)
                }
                shelfPendingEmpty = nil
            }
            Button(l10n.t("Zrušit", "Cancel"), role: .cancel) {
                shelfPendingEmpty = nil
            }
        } message: {
            Text(l10n.t(
                "Odeberou se pouze odkazy v poličce. Původní soubory na disku zůstanou.",
                "Only shelf references will be removed. Original files on disk remain untouched."
            ))
        }
        .confirmationDialog(
            l10n.t("Odstranit poličku „\(shelfPendingDelete?.name ?? "")“?", "Delete shelf “\(shelfPendingDelete?.name ?? "")”?"),
            isPresented: Binding(
                get: { shelfPendingDelete != nil },
                set: { if !$0 { shelfPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(l10n.t("Odstranit poličku", "Delete Shelf"), role: .destructive) {
                if let shelf = shelfPendingDelete {
                    store.deleteShelf(id: shelf.id)
                }
                shelfPendingDelete = nil
            }
            Button(l10n.t("Zrušit", "Cancel"), role: .cancel) {
                shelfPendingDelete = nil
            }
        } message: {
            Text(l10n.t(
                "Smaže se polička a její odkazy. Původní soubory na disku zůstanou.",
                "The shelf and its references will be deleted. Original files on disk remain untouched."
            ))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func shelfRow(_ shelf: Shelf) -> some View {
        let isExpanded = expandedShelfID == shelf.id

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    onSelectShelf(shelf.id)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ShelfColorPalette.color(for: shelf))
                            .frame(width: 9, height: 9)

                        if renamingShelfID == shelf.id {
                            TextField("Název", text: $draftName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .onSubmit {
                                    store.renameShelf(id: shelf.id, to: draftName)
                                    renamingShelfID = nil
                                }
                                .onExitCommand {
                                    renamingShelfID = nil
                                }
                        } else {
                            Text(shelf.name)
                                .font(.system(size: 12.5, weight: shelf.isVisible ? .medium : .regular))
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("\(shelf.items.count)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    onToggleShelfVisibility(shelf.id)
                } label: {
                    Image(systemName: shelf.isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(shelf.isVisible ? .primary : .tertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(shelf.isVisible ? "Skrýt poličku" : "Zobrazit poličku")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedShelfID = isExpanded ? nil : shelf.id
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 20)
                }
                .buttonStyle(.plain)
                .help("Možnosti poličky")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isExpanded ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 6)
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Inline color picker
                    HStack(spacing: 7) {
                        Text(l10n.t("Barva:", "Color:"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        ForEach(ShelfColor.allCases, id: \.self) { color in
                            Button {
                                store.setShelfColor(id: shelf.id, color: color)
                                hexEditingShelfID = nil
                                hexError = false
                            } label: {
                                let isSelected = shelf.customColorHex == nil && shelf.colorID == color
                                Circle()
                                    .fill(ShelfColorPalette.color(for: color))
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: isSelected ? 2 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(l10n.colorName(color))
                        }

                        if let customHex = shelf.customColorHex {
                            Button {
                                if hexEditingShelfID == shelf.id {
                                    hexEditingShelfID = nil
                                } else {
                                    hexInput = customHex
                                    hexError = false
                                    hexEditingShelfID = shelf.id
                                }
                            } label: {
                                Circle()
                                    .fill(ShelfColorPalette.color(for: shelf))
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(l10n.t("Vlastní barva: \(customHex)", "Custom color: \(customHex)"))
                        }

                        Button {
                            ShelfColorPanelCoordinator.shared.open(for: shelf) { hex in
                                _ = store.setShelfCustomColorHex(id: shelf.id, hex: hex)
                                if hexEditingShelfID == shelf.id {
                                    hexInput = hex
                                    hexError = false
                                }
                            }
                        } label: {
                            Image(systemName: "paintpalette")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(l10n.t("Barevné kolo a kapátko", "Color Wheel & Eyedropper"))

                        Button {
                            if hexEditingShelfID == shelf.id {
                                hexEditingShelfID = nil
                            } else {
                                hexInput = shelf.customColorHex ?? "#"
                                hexError = false
                                hexEditingShelfID = shelf.id
                            }
                        } label: {
                            Image(systemName: "number.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(shelf.customColorHex != nil ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(l10n.t("Vlastní hex barva (#RRGGBB)", "Custom Hex Color (#RRGGBB)"))

                        Spacer()

                        Button {
                            store.moveShelf(id: shelf.id, direction: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .controlSize(.small)
                        .help(l10n.t("Posunout výš", "Move Up"))

                        Button {
                            store.moveShelf(id: shelf.id, direction: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .controlSize(.small)
                        .help(l10n.t("Posunout níž", "Move Down"))
                    }

                    if let customHex = shelf.customColorHex, hexEditingShelfID != shelf.id {
                        HStack(spacing: 6) {
                            Text(l10n.t("Vlastní:", "Custom:"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(ShelfColorPalette.color(for: shelf))
                                .frame(width: 10, height: 10)
                            Text(customHex)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    if hexEditingShelfID == shelf.id {
                        HStack(spacing: 6) {
                            TextField("#FF6B35", text: $hexInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 96)
                                .onSubmit {
                                    applyHex(for: shelf.id)
                                }

                            if let preview = ShelfColorPalette.color(fromHex: hexInput) {
                                Circle()
                                    .fill(preview)
                                    .frame(width: 14, height: 14)
                            }

                            Button(l10n.t("Použít", "Apply")) {
                                applyHex(for: shelf.id)
                            }
                            .controlSize(.small)

                            if hexError {
                                Text(l10n.t("Neplatný hex", "Invalid hex"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    // Inline action buttons (popover stays open!)
                    HStack(spacing: 6) {
                        Button(l10n.t("Přejmenovat", "Rename")) {
                            draftName = shelf.name
                            renamingShelfID = shelf.id
                        }
                        .controlSize(.small)

                        Button(shelf.isPinned ? l10n.t("Odepnout", "Unpin") : l10n.t("Připnout", "Pin")) {
                            store.setShelfPinned(id: shelf.id, isPinned: !shelf.isPinned)
                        }
                        .controlSize(.small)

                        Spacer()

                        Button(l10n.t("Vyprázdnit", "Empty")) {
                            if shelf.items.isEmpty {
                                store.emptyShelf(id: shelf.id)
                            } else {
                                shelfPendingEmpty = shelf
                            }
                        }
                        .controlSize(.small)
                        .disabled(shelf.items.isEmpty)

                        Button(role: .destructive) {
                            if shelf.items.isEmpty {
                                store.deleteShelf(id: shelf.id)
                            } else {
                                shelfPendingDelete = shelf
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                        .help(l10n.t("Odstranit poličku", "Delete Shelf"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.04))
                        .padding(.horizontal, 10)
                )
            }
        }
    }

    private func footerButton(title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applyHex(for shelfID: UUID) {
        if store.setShelfCustomColorHex(id: shelfID, hex: hexInput) {
            hexError = false
            hexEditingShelfID = nil
        } else {
            hexError = true
        }
    }
}
