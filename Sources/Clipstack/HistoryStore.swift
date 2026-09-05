import AppKit
import ImageIO

/// Owns the history list, persists it to ~/Library/Application Support/Clipstack,
/// and hands out cached thumbnails / app icons for the UI.
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    /// Maximum number of unpinned entries kept. Pinned entries never count.
    var maxItems = 200

    private let directory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var appIconCache: [String: NSImage] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("Clipstack", isDirectory: true)
        imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        indexURL = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        thumbnailCache.countLimit = 100
        load()
    }

    /// Pinned entries first, then everything else, both newest first.
    var displayItems: [ClipItem] {
        items.filter(\.pinned) + items.filter { !$0.pinned }
    }

    // MARK: - Mutations

    func ingest(_ captured: Captured, source: String?) {
        let hash = captured.hash
        if let index = items.firstIndex(where: { $0.hash == hash }) {
            // Same content copied again: move the existing entry to the top.
            var existing = items.remove(at: index)
            existing.date = Date()
            if let source { existing.sourceBundleID = source }
            items.insert(existing, at: 0)
            scheduleSave()
            return
        }

        let id = UUID()
        var item: ClipItem
        switch captured {
        case .text(let string, let rtf):
            item = ClipItem(id: id, kind: .text, date: Date(), pinned: false, hash: hash, sourceBundleID: source)
            item.text = string
            item.rtf = rtf
            item.charCount = string.count
            item.lineCount = string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        case .image(let png, let width, let height):
            let fileName = id.uuidString + ".png"
            do {
                try png.write(to: imagesDirectory.appendingPathComponent(fileName), options: .atomic)
            } catch {
                NSLog("Clipstack: failed to store image: \(error)")
                return
            }
            item = ClipItem(id: id, kind: .image, date: Date(), pinned: false, hash: hash, sourceBundleID: source)
            item.imageFile = fileName
            item.imageWidth = width
            item.imageHeight = height
        case .files(let paths):
            item = ClipItem(id: id, kind: .files, date: Date(), pinned: false, hash: hash, sourceBundleID: source)
            item.files = paths
        }

        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    /// Marks an entry as just used: moves it to the top of the list.
    func touch(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.date = Date()
        items.insert(item, at: 0)
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        trim()
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        deleteImageFile(of: item)
        scheduleSave()
    }

    func clear(keepPinned: Bool = true) {
        let removed = keepPinned ? items.filter { !$0.pinned } : items
        removed.forEach(deleteImageFile)
        items = keepPinned ? items.filter(\.pinned) : []
        thumbnailCache.removeAllObjects()
        scheduleSave()
    }

    // MARK: - Images

    func imageURL(for item: ClipItem) -> URL? {
        guard let file = item.imageFile else { return nil }
        return imagesDirectory.appendingPathComponent(file)
    }

    func imageData(for item: ClipItem) -> Data? {
        guard let url = imageURL(for: item) else { return nil }
        return try? Data(contentsOf: url)
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let file = item.imageFile, let url = imageURL(for: item) else { return nil }
        let key = file as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = appIconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        appIconCache[bundleID] = icon
        return icon
    }

    // MARK: - Persistence

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("Clipstack: failed to save history: \(error)")
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([ClipItem].self, from: data)
            items = decoded
                .filter { item in
                    // Drop image entries whose file has gone missing.
                    guard let url = imageURL(for: item) else { return true }
                    return FileManager.default.fileExists(atPath: url.path)
                }
                .sorted { $0.date > $1.date }
        } catch {
            NSLog("Clipstack: failed to load history: \(error)")
        }
        cleanupOrphanImages()
    }

    private func trim() {
        var unpinned = items.filter { !$0.pinned }.count
        guard unpinned > maxItems else { return }
        for index in stride(from: items.count - 1, through: 0, by: -1) where unpinned > maxItems {
            if items[index].pinned { continue }
            deleteImageFile(of: items[index])
            items.remove(at: index)
            unpinned -= 1
        }
    }

    private func deleteImageFile(of item: ClipItem) {
        guard let url = imageURL(for: item) else { return }
        thumbnailCache.removeObject(forKey: (item.imageFile ?? "") as NSString)
        try? FileManager.default.removeItem(at: url)
    }

    private func cleanupOrphanImages() {
        let referenced = Set(items.compactMap(\.imageFile))
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path) else { return }
        for file in files where !referenced.contains(file) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
        }
    }
}
