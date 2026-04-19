import XCTest
@testable import Harvest

final class SessionStoreTests: XCTestCase {

    private func makeUser() -> HarvestUser {
        HarvestUser(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            email: "a@b.com",
            name: nil,
            onboarded: false
        )
    }

    func testHydratesFromPersistenceOnInit() {
        let persistence = InMemorySessionPersistence(token: "abc", user: makeUser())
        let store = SessionStore(persistence: persistence)

        XCTAssertEqual(store.token, "abc")
        XCTAssertEqual(store.user?.email, "a@b.com")
        XCTAssertTrue(store.isAuthenticated)
    }

    func testSaveWritesThroughToPersistence() {
        let persistence = InMemorySessionPersistence()
        let store = SessionStore(persistence: persistence)
        XCTAssertFalse(store.isAuthenticated)

        store.save(token: "xyz", user: makeUser())

        XCTAssertEqual(persistence.readToken(), "xyz")
        XCTAssertEqual(persistence.readUser()?.email, "a@b.com")
    }

    func testClearRemovesTokenAndUser() {
        let persistence = InMemorySessionPersistence(token: "abc", user: makeUser())
        let store = SessionStore(persistence: persistence)

        store.clear()

        XCTAssertNil(store.token)
        XCTAssertNil(store.user)
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(persistence.readToken())
        XCTAssertNil(persistence.readUser())
    }

    func testUpdateUserLeavesTokenIntact() {
        let persistence = InMemorySessionPersistence(token: "abc", user: makeUser())
        let store = SessionStore(persistence: persistence)

        let renamed = HarvestUser(
            id: makeUser().id,
            email: "a@b.com",
            name: "Alice",
            onboarded: true
        )
        store.updateUser(renamed)

        XCTAssertEqual(store.token, "abc")
        XCTAssertEqual(store.user?.name, "Alice")
        XCTAssertTrue(store.user?.onboarded ?? false)
    }
}
