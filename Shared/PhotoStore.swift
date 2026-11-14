import Foundation

struct StoredPhoto: Identifiable {
    let id: UUID
    let url: URL
    let date: Date
}

struct PhotoStore {
    static let defaultLimit = 20
    let directory: URL
    var limit = defaultLimit

    func prepare() throws -> [StoredPhoto] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try retainNewest()
    }

    func photos() throws -> [StoredPhoto] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
                                                               includingPropertiesForKeys: Array(keys))
        return try urls.compactMap { url -> StoredPhoto? in
            guard ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()),
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return StoredPhoto(id: id, url: url, date: values.creationDate ?? values.contentModificationDate ?? .distantPast)
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
    }

    /// Deletes files directly, without leaving copies in Trash.
    @discardableResult
    func retainNewest() throws -> [StoredPhoto] {
        precondition(limit > 0)
        let stored = try photos()
        let excess = max(0, stored.count - limit)
        for photo in stored.prefix(excess) {
            try FileManager.default.removeItem(at: photo.url)
        }
        return Array(stored.dropFirst(excess))
    }

    func contains(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    func url(for id: UUID) -> URL {
        for ext in ["jpg", "jpeg", "png"] {
            let candidate = directory.appendingPathComponent("\(id.uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    @discardableResult
    func save(_ data: Data, id: UUID, isPNG: Bool = false) throws -> [StoredPhoto] {
        if !contains(id) {
            let destination = directory.appendingPathComponent("\(id.uuidString).\(isPNG ? "png" : "jpg")")
            try data.write(to: destination, options: .atomic)
        }
        return try retainNewest()
    }
}
