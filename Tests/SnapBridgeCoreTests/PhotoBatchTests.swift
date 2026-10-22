import XCTest
@testable import SnapBridgeCore

final class PhotoBatchTests: XCTestCase {
    func testSuccessivePhotosJoinUntilPopupCloses() {
        let a = UUID(), b = UUID(), c = UUID()
        var batch = PhotoBatch()
        batch.append(a, retained: [a])
        batch.append(b, retained: [a, b])
        XCTAssertEqual(batch.ids, [a, b])
        batch.close()
        batch.append(c, retained: [a, b, c])
        XCTAssertEqual(batch.ids, [c], "Previously copied photos must not leak into the next group")
    }

    func testRetryDoesNotDuplicateAnAttachment() {
        let id = UUID()
        var batch = PhotoBatch()
        batch.append(id, retained: [id])
        batch.append(id, retained: [id])
        XCTAssertEqual(batch.ids, [id])
    }

    func testEvictedFilesAreRemovedFromTheBatchAndClipboardList() {
        var batch = PhotoBatch()
        let ids = (0..<25).map { _ in UUID() }
        for index in ids.indices {
            batch.append(ids[index], retained: Set(ids[max(0, index - 19)...index]))
        }
        XCTAssertEqual(batch.ids, Array(ids.suffix(20)))
    }
}
