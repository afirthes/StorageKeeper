import CryptoKit
import Foundation

actor PhotoCache {
    static let shared = PhotoCache()

    private let memoryCache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let expirationInterval: TimeInterval = 60 * 60 * 24 * 30
    private let maximumDiskBytes: Int64 = 512 * 1024 * 1024

    init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = cachesURL.appendingPathComponent("StorageKeeperPhotoCache", isDirectory: true)
        memoryCache.totalCostLimit = 60 * 1024 * 1024
        memoryCache.countLimit = 300

        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectoryURL = directoryURL
        try? mutableDirectoryURL.setResourceValues(resourceValues)
    }

    func data(for key: String) async -> Data? {
        let cacheKey = key as NSString

        if let data = memoryCache.object(forKey: cacheKey) {
            return data as Data
        }

        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        guard !isExpired(url) else {
            try? fileManager.removeItem(at: url)
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            try? fileManager.removeItem(at: url)
            return nil
        }

        touch(url)
        memoryCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        return data
    }

    func store(_ data: Data, for key: String) async {
        guard !data.isEmpty else {
            return
        }

        let cacheKey = key as NSString
        memoryCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)

        let url = fileURL(for: key)
        do {
            try data.write(to: url, options: [.atomic])
            excludeFromBackup(url)
            touch(url)
            try await pruneIfNeeded()
        } catch {
            try? fileManager.removeItem(at: url)
        }
    }

    func remove(keys: [String]) async {
        for key in keys {
            memoryCache.removeObject(forKey: key as NSString)
            try? fileManager.removeItem(at: fileURL(for: key))
        }
    }

    func removeAll() async {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: directoryURL)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func pruneIfNeeded() async throws {
        let files = cachedFiles()
        let now = Date()
        var freshFiles: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0

        for file in files {
            if now.timeIntervalSince(file.date) > expirationInterval {
                try? fileManager.removeItem(at: file.url)
                continue
            }

            freshFiles.append(file)
            totalSize += file.size
        }

        guard totalSize > maximumDiskBytes else {
            return
        }

        for file in freshFiles.sorted(by: { $0.date < $1.date }) {
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size

            if totalSize <= maximumDiskBytes {
                break
            }
        }
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func isExpired(_ url: URL) -> Bool {
        guard let date = resourceValues(for: url).contentModificationDate else {
            return false
        }

        return Date().timeIntervalSince(date) > expirationInterval
    }

    private func touch(_ url: URL) {
        let now = Date()
        try? fileManager.setAttributes([
            .modificationDate: now,
            .creationDate: resourceValues(for: url).creationDate ?? now,
        ], ofItemAtPath: url.path)
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private func cachedFiles() -> [(url: URL, size: Int64, date: Date)] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            let values = resourceValues(for: url)
            let size = Int64(values.fileSize ?? 0)
            let date = values.contentModificationDate ?? values.creationDate ?? .distantPast
            return (url, size, date)
        }
    }

    private func resourceValues(for url: URL) -> URLResourceValues {
        (try? url.resourceValues(forKeys: [
            .creationDateKey,
            .contentAccessDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ])) ?? URLResourceValues()
    }
}
