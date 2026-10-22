import Foundation

/// A popup's lifetime defines a batch. Closing it starts the next photo afresh.
struct PhotoBatch {
    private(set) var ids: [UUID] = []

    mutating func append(_ id: UUID, retained: Set<UUID>) {
        ids.removeAll { !retained.contains($0) }
        if retained.contains(id), !ids.contains(id) { ids.append(id) }
        ids = Array(ids.suffix(20))
    }

    mutating func close() { ids = [] }
}
