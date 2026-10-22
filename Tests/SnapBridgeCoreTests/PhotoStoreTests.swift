import XCTest
@testable import SnapBridgeCore

final class PhotoStoreTests: XCTestCase {
    private var folder: URL!
    private var store: PhotoStore!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = PhotoStore(directory: folder)
        _ = try store.prepare()
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    private func seed(_ count: Int) throws -> [UUID] {
        try (0..<count).map { index in
            let id = UUID()
            let url = store.url(for: id)
            try Data([UInt8(index % 255)]).write(to: url)
            try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))],
                                                  ofItemAtPath: url.path)
            return id
        }
    }

    func testTwentyFirstPhotoPermanentlyRemovesTheOldest() throws {
        let ids = try seed(20)
        let newest = UUID()
        let retained = try store.save(Data([42]), id: newest)
        XCTAssertEqual(retained.count, 20)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: ids[0]).path))
        XCTAssertEqual(retained.map(\.id), Array(ids.dropFirst()) + [newest])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 20)
    }

    func testStartupRemovesExistingExcessPhotosInOrder() throws {
        let ids = try seed(47)
        let retained = try store.prepare()
        XCTAssertEqual(retained.map(\.id), Array(ids.suffix(20)))
        XCTAssertTrue(ids.prefix(27).allSatisfy { !store.contains($0) })
    }

    func testUnderLimitAndRepeatedCleanupKeepPhotosUnchanged() throws {
        let ids = try seed(8)
        XCTAssertEqual(try store.retainNewest().map(\.id), ids)
        XCTAssertEqual(try store.retainNewest().map(\.id), ids)
        XCTAssertEqual(try Data(contentsOf: store.url(for: ids[0])), Data([0]))
    }

    func testDuplicateDoesNotRewriteOrEvictAnotherPhoto() throws {
        let ids = try seed(20)
        let retained = try store.save(Data([99]), id: ids[0])
        XCTAssertEqual(retained.map(\.id), ids)
        XCTAssertEqual(try Data(contentsOf: store.url(for: ids[0])), Data([0]))
    }

    func testCleanupOnlyRemovesManagedPhotoFiles() throws {
        _ = try seed(25)
        let note = folder.appendingPathComponent("notes.txt")
        let unrelated = folder.appendingPathComponent("my-picture.jpg")
        try Data("keep".utf8).write(to: note)
        try Data("keep".utf8).write(to: unrelated)
        let outside = folder.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let symlink = store.url(for: UUID())
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        XCTAssertEqual(try store.retainNewest().count, 20)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlink.path))
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
    }
}
