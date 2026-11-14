import AppKit
@preconcurrency import Quartz

/// Manages native macOS Quick Look (`QLPreviewPanel`) for selected shelf items.
@MainActor
final class QuickLookService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookService()

    private var previewURLs: [URL] = []

    private override init() {
        super.init()
    }

    func togglePreview(for urls: [URL]) {
        let validURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty, let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible && previewURLs == validURLs {
            panel.orderOut(nil)
            return
        }

        previewURLs = validURLs
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            previewURLs.count
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard index >= 0 && index < previewURLs.count else { return nil }
            return previewURLs[index] as NSURL
        }
    }
}
