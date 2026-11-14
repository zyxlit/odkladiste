import AppKit
import SwiftUI
import OdkladisteCore

enum ShelfColorPalette {
    static func color(for shelf: Shelf) -> Color {
        if let hex = shelf.customColorHex, let parsed = color(fromHex: hex) {
            return parsed
        }
        return color(for: shelf.colorID)
    }

    static func nsColor(for shelf: Shelf) -> NSColor {
        if let hex = shelf.customColorHex, let parsed = nsColor(fromHex: hex) {
            return parsed
        }
        switch shelf.colorID {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .graphite: return .systemGray
        }
    }

    static func color(for colorID: ShelfColor) -> Color {
        switch colorID {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .graphite: return .gray
        }
    }

    static func color(fromHex raw: String) -> Color? {
        guard let (r, g, b) = rgbComponents(fromHex: raw) else { return nil }
        return Color(red: r, green: g, blue: b)
    }

    static func nsColor(fromHex raw: String) -> NSColor? {
        guard let (r, g, b) = rgbComponents(fromHex: raw) else { return nil }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    static func hexString(from nsColor: NSColor) -> String? {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        let r = Int((min(max(srgb.redComponent, 0), 1) * 255.0).rounded())
        let g = Int((min(max(srgb.greenComponent, 0), 1) * 255.0).rounded())
        let b = Int((min(max(srgb.blueComponent, 0), 1) * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func rgbComponents(fromHex raw: String) -> (Double, Double, Double)? {
        guard let normalized = Shelf.normalizedHex(raw) else { return nil }
        let hexString = String(normalized.dropFirst())
        var rgb: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return (r, g, b)
    }
}

@MainActor
final class ShelfColorPanelCoordinator: NSObject {
    static let shared = ShelfColorPanelCoordinator()

    private var onSelectHex: ((String) -> Void)?
    private var isConfiguringPanel = false

    func open(for shelf: Shelf, onSelectHex: @escaping (String) -> Void) {
        self.onSelectHex = onSelectHex

        let panel = NSColorPanel.shared
        isConfiguringPanel = true
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.mode = .wheel
        panel.color = ShelfColorPalette.nsColor(for: shelf)
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        isConfiguringPanel = false

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        guard !isConfiguringPanel, let hex = ShelfColorPalette.hexString(from: sender.color) else { return }
        onSelectHex?(hex)
    }
}
