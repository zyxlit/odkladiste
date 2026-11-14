import AppKit
import SwiftUI
import CoreGraphics
import OdkladisteCore

enum ShelfKeyCommand {
    case selectAll
    case toggleSearch
    case quickLook
    case deleteSelected
    case undo
    case redo
    case escape
}

extension Notification.Name {
    static let shelfKeyCommand = Notification.Name("OdkladisteShelfKeyCommand")
}

/// Non-activating floating panel that allows text field focus only when needed.
final class ShelfPanel: NSPanel {
    var shelfID: UUID?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEditingTextField {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == .command {
            switch chars {
            case "a":
                post(.selectAll); return true
            case "f":
                post(.toggleSearch); return true
            case "z":
                post(.undo); return true
            case "w":
                _ = delegate?.windowShouldClose?(self)
                return true
            default:
                break
            }
        } else if flags == [.command, .shift], chars == "z" {
            post(.redo); return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isEditingTextField {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 49: // Space
            post(.quickLook)
        case 51, 117: // Backspace, Forward Delete
            post(.deleteSelected)
        case 53: // Escape
            post(.escape)
        default:
            super.keyDown(with: event)
        }
    }

    private var isEditingTextField: Bool {
        firstResponder is NSTextView
    }

    private func post(_ command: ShelfKeyCommand) {
        guard let shelfID else { return }
        NotificationCenter.default.post(
            name: .shelfKeyCommand,
            object: nil,
            userInfo: ["shelfID": shelfID, "command": command]
        )
    }
}

/// Manages the lifecycle, placement, and multi-monitor clamping of a single shelf's `NSPanel`.
@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    let shelfID: UUID
    private let store: ShelfStore
    let panel: ShelfPanel
    private var isProgrammaticMove = false

    init(shelf: Shelf, store: ShelfStore) {
        self.shelfID = shelf.id
        self.store = store

        let screens = Self.currentScreenDescriptors()
        let initialRect = DisplayPlacement.resolveFrame(for: shelf.windowPlacement, screens: screens)

        self.panel = ShelfPanel(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.shelfID = shelf.id
        panel.delegate = self
        panel.title = shelf.name
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.minSize = DisplayPlacement.minimumSize
        panel.level = shelf.isAlwaysOnTop ? .floating : .normal
        let allSpaces = UserDefaults.standard.object(forKey: "odkladiste.allSpaces") as? Bool ?? true
        panel.collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Hide system titlebar buttons; the header provides an accessible close/hide button.
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = ShelfPanelRootView(shelfID: shelf.id, store: store, onRequestRenameFocus: { [weak self] in
            self?.panel.makeKeyAndOrderFront(nil)
        })
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let dropContainer = ShelfDropZoneNSView(shelfID: shelf.id, store: store)
        dropContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: dropContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: dropContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: dropContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: dropContainer.bottomAnchor)
        ])

        panel.contentView = dropContainer
    }

    func updateAllSpaces(_ enabled: Bool) {
        panel.collectionBehavior = enabled
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    func show() {
        ensureVisibleOnScreen()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func sync(with shelf: Shelf) {
        panel.title = shelf.name
        panel.level = shelf.isAlwaysOnTop ? .floating : .normal
        if shelf.isVisible {
            if !panel.isVisible {
                show()
            }
        } else if panel.isVisible {
            hide()
        }
    }

    func ensureVisibleOnScreen() {
        let screens = Self.currentScreenDescriptors()
        let currentPlacement = store.shelf(id: shelfID)?.windowPlacement
            ?? WindowPlacement(displayUUID: Self.displayUUID(for: panel.screen), rect: panel.frame)
        let resolved = DisplayPlacement.resolveFrame(for: currentPlacement, screens: screens)
        if resolved != panel.frame {
            isProgrammaticMove = true
            panel.setFrame(resolved, display: true)
            isProgrammaticMove = false
            persistCurrentPlacement()
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        store.setShelfVisible(id: shelfID, isVisible: false)
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove else { return }
        persistCurrentPlacement()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isProgrammaticMove else { return }
        persistCurrentPlacement()
    }

    private func persistCurrentPlacement() {
        let uuid = Self.displayUUID(for: panel.screen)
        let placement = WindowPlacement(displayUUID: uuid, rect: panel.frame)
        store.updatePlacement(for: shelfID, placement: placement)
    }

    // MARK: - Display Helpers

    static func currentScreenDescriptors() -> [ScreenDescriptor] {
        NSScreen.screens.map { screen in
            ScreenDescriptor(
                displayUUID: displayUUID(for: screen),
                visibleFrame: screen.visibleFrame
            )
        }
    }

    static func displayUUID(for screen: NSScreen?) -> String? {
        guard let screen,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String?
    }
}
