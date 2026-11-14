import AppKit
@preconcurrency import QuickLookThumbnailing
import SwiftUI

/// Bounded, asynchronous Quick Look thumbnail loader with `NSCache` and system icon fallback.
@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 300
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    private init() {}

    func clearCache() {
        cache.removeAllObjects()
    }

    func loadThumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let fallback = NSWorkspace.shared.icon(forFile: url.path)
        fallback.size = size

        guard FileManager.default.fileExists(atPath: url.path) else {
            return fallback
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let image = representation.nsImage
            cache.setObject(image, forKey: key)
            return image
        } catch {
            cache.setObject(fallback, forKey: key)
            return fallback
        }
    }
}

/// SwiftUI view that asynchronously loads a Quick Look thumbnail for a file URL and cancels on disappear.
struct FileThumbnailView: View {
    let url: URL
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(url.path)|\(Int(size))") {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let loaded = await ThumbnailService.shared.loadThumbnail(
                for: url,
                size: CGSize(width: size, height: size),
                scale: scale
            )
            if !Task.isCancelled {
                image = loaded
            }
        }
    }
}
