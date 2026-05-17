import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - LibraryEntry

struct LibraryEntry {
    let id: UUID
    var libraryURL: URL
    var capturedAt: Date
    var thumbnailImage: NSImage?
}

// MARK: - LibraryManager

class LibraryManager {
    static let shared = LibraryManager()
    private init() {}

    static let defaultLibraryPath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Grabbit/Library").path
    }()

    var libraryPath: String {
        get { UserDefaults.standard.string(forKey: Prefs.libraryPath) ?? LibraryManager.defaultLibraryPath }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.libraryPath) }
    }

    var libraryURL: URL { URL(fileURLWithPath: libraryPath) }

    func ensureLibraryDirectory() {
        let url = libraryURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Save / Update

    /// Saves a captured image as a timestamped PNG and returns the URL.
    /// Must be called from the main thread — use saveCaptureCG for background threads.
    func saveCapture(_ image: NSImage) -> URL? {
        ensureLibraryDirectory()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let ts = fmt.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = libraryURL.appendingPathComponent("\(ts).png")
        return writePNG(image, to: url) ? url : nil
    }

    /// Thread-safe variant: writes a CGImage directly without any NSImage drawing.
    /// CGImage is immutable and safe to pass across threads.
    func saveCaptureCG(_ cgImage: CGImage) -> URL? {
        ensureLibraryDirectory()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let ts = fmt.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = libraryURL.appendingPathComponent("\(ts).png")
        return writePNGFromCG(cgImage, to: url) ? url : nil
    }

    // MARK: - Annotation sidecar

    /// The URL of the .grabbit sidecar that lives alongside a library image.
    func sidecarURL(for imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension("grabbit")
    }

    /// Writes (or overwrites) the annotation sidecar for a library image.
    func updateSidecar(for imageURL: URL, data: GrabbitDocumentData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(data) else { return }
        try? jsonData.write(to: sidecarURL(for: imageURL))
    }

    /// Reads the annotation sidecar for a library image, or returns nil if none exists.
    func loadSidecar(for imageURL: URL) -> GrabbitDocumentData? {
        let url = sidecarURL(for: imageURL)
        guard let jsonData = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GrabbitDocumentData.self, from: jsonData)
    }

    // MARK: - Load

    /// Enumerates the library directory and returns entries sorted newest→oldest.
    func loadEntries(excluding excluded: Set<URL> = []) -> [LibraryEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let allowed = Set(["png", "jpg", "jpeg", "tiff", "tif"])
        // .grabbit files are annotation sidecars — filter them out here.
        return items
            .filter { allowed.contains($0.pathExtension.lowercased()) && !excluded.contains($0) }
            .compactMap { url -> LibraryEntry? in
                let res = try? url.resourceValues(forKeys: [.creationDateKey])
                let date = res?.creationDate ?? Date.distantPast
                let thumb = NSImage(contentsOf: url).map { makeThumbnail($0) }
                return LibraryEntry(id: UUID(), libraryURL: url, capturedAt: date, thumbnailImage: thumb)
            }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    // MARK: - Thumbnail generation

    func makeThumbnail(_ image: NSImage, maxSide: CGFloat = 300) -> NSImage {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return image }
        let scale = min(1.0, min(maxSide / w, maxSide / h))
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .medium
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        image.draw(in: CGRect(x: 0, y: 0, width: tw, height: th))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: tw, height: th))
    }

    /// Thread-safe thumbnail from a CGImage — uses Core Graphics only, no NSImage drawing.
    func makeThumbnailCG(_ cgImage: CGImage, originalSize: NSSize, maxSide: CGFloat = 300) -> NSImage {
        let w = originalSize.width, h = originalSize.height
        guard w > 0, h > 0 else { return NSImage(cgImage: cgImage, size: originalSize) }
        let scale = min(1.0, min(maxSide / w, maxSide / h))
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(cgImage: cgImage, size: originalSize) }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let cg = ctx.makeImage() else { return NSImage(cgImage: cgImage, size: originalSize) }
        return NSImage(cgImage: cg, size: NSSize(width: tw, height: th))
    }

    // MARK: - Private helpers

    /// Writes a CGImage to disk as PNG with 72 DPI metadata. Thread-safe.
    private func writePNGFromCG(_ cgImage: CGImage, to url: URL) -> Bool {
        guard cgImage.width > 0, cgImage.height > 0,
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        let props: [CFString: Any] = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    private func writePNG(_ image: NSImage, to url: URL) -> Bool {
        let w = Int(image.size.width), h = Int(image.size.height)
        guard w > 0, h > 0,
              let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        let props: [CFString: Any] = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
