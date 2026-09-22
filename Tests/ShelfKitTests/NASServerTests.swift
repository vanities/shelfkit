import XCTest
@testable import ShelfKit

/// Both apps keep their NAS servers in their library files; the shared type must read what
/// the apps' own copies of it wrote.
final class NASServerTests: XCTestCase {
    /// Written by the NASServer each app had before ShelfKit (same keys, same shapes).
    private let savedByAnOlderBuild = """
    {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"NAS","host":"192.168.1.3","port":445,
     "share":"all","path":"downloads/books","username":"adam","domain":"","addedAt":780000000}
    """

    func testReadsWhatTheAppsWrote() throws {
        let server = try JSONDecoder().decode(NASServer.self, from: Data(savedByAnOlderBuild.utf8))
        XCTAssertEqual(server.name, "NAS")
        XCTAssertEqual(server.port, 445)
        XCTAssertEqual(server.path, "downloads/books")
        XCTAssertEqual(server.addedAt, Date(timeIntervalSinceReferenceDate: 780_000_000))
    }

    func testRoundTrips() throws {
        let server = NASServer(id: UUID(), name: "Test SMB", host: "127.0.0.1", port: 1445, share: "manga",
                               path: "", username: "tester", addedAt: Date(timeIntervalSinceReferenceDate: 1))
        let decoded = try JSONDecoder().decode(NASServer.self, from: JSONEncoder().encode(server))
        XCTAssertEqual(decoded, server)
    }

    func testLocationShowsAPortOnlyWhenItIsNotTheDefault() {
        var server = NASServer(id: UUID(), name: "NAS", host: "nas.local", share: "all", path: "books",
                               username: "", addedAt: .now)
        XCTAssertEqual(server.displayLocation, "smb://nas.local/all/books")
        server.port = 1445
        XCTAssertEqual(server.displayLocation, "smb://nas.local:1445/all/books")
    }

    func testRemotePathsJoinOntoTheLibraryRoot() {
        let rooted = NASServer(id: UUID(), name: "", host: "h", share: "s", path: "downloads/books", username: "", addedAt: .now)
        XCTAssertEqual(rooted.remotePath(for: "Author/Book"), "downloads/books/Author/Book")
        let bare = NASServer(id: UUID(), name: "", host: "h", share: "s", path: "", username: "", addedAt: .now)
        XCTAssertEqual(bare.remotePath(for: "Author/Book"), "Author/Book")
    }
}
