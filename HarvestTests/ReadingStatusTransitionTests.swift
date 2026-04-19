import XCTest
@testable import Harvest

final class ReadingStatusTransitionTests: XCTestCase {

    func testUnreadOffersMarkReadAndArchive() {
        let transitions = ReadingStatus.unread.availableTransitions
        XCTAssertEqual(transitions.map(\.target), [.read, .archived])
        XCTAssertEqual(transitions.map(\.label), ["Mark read", "Archive"])
    }

    func testReadOffersOnlyArchiveAndNeverMarkUnread() {
        let transitions = ReadingStatus.read.availableTransitions
        XCTAssertEqual(transitions.map(\.target), [.archived])
        XCTAssertFalse(
            transitions.contains { $0.target == .unread },
            "read → unread is a 422 on the server (handoff §5); don't offer it"
        )
    }

    func testArchivedOffersUnarchiveTargetingReadNotUnread() {
        // handoff §5 quirk: archived → "unread" silently becomes `read`. We
        // offer a single Unarchive button that *targets* .read directly, so
        // the client never depends on the quirk.
        let transitions = ReadingStatus.archived.availableTransitions
        XCTAssertEqual(transitions.map(\.target), [.read])
        XCTAssertEqual(transitions.map(\.label), ["Unarchive"])
    }
}
