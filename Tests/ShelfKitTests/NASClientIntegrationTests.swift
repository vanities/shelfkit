import XCTest
@testable import ShelfKit

/// Against a real SMB share, only when one is named in the environment — e.g. the Docker test
/// share both apps use:
///
///     SHELFKIT_SMB_HOST=127.0.0.1 SHELFKIT_SMB_PORT=1445 SHELFKIT_SMB_SHARE=manga \
///     SHELFKIT_SMB_USER=… SHELFKIT_SMB_PASSWORD=… swift test --filter NASClientIntegrationTests
///
/// Credentials never live in this repo.
final class NASClientIntegrationTests: XCTestCase {
    private func client() throws -> NASClient {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["SHELFKIT_SMB_HOST"], let share = env["SHELFKIT_SMB_SHARE"] else {
            throw XCTSkip("No SMB share named in the environment")
        }
        let server = NASServer(id: UUID(), name: "Test", host: host, port: Int(env["SHELFKIT_SMB_PORT"] ?? "") ?? 445,
                               share: share, path: env["SHELFKIT_SMB_PATH"] ?? "", username: env["SHELFKIT_SMB_USER"] ?? "",
                               addedAt: .now)
        return try NASClient(server: server, password: env["SHELFKIT_SMB_PASSWORD"] ?? "")
    }

    /// The first file somewhere in the first few folders — the share's layout isn't assumed.
    private func someFile(_ client: NASClient) async throws -> NASEntry {
        var folders = [""]
        while let folder = folders.first, folders.count < 50 {
            folders.removeFirst()
            let entries = try await client.list(folder)
            if let file = entries.first(where: { !$0.isDirectory && $0.size > 0 }) { return file }
            folders += entries.filter(\.isDirectory).map(\.relativePath)
        }
        throw XCTSkip("No file found on the share")
    }

    func testListReadAndDownloadAgree() async throws {
        let client = try client()
        try await client.connect()
        let file = try await someFile(client)
        let size = try await client.fileSize(file.relativePath)
        XCTAssertEqual(size, file.size, "the listing and the file agree on its size")

        // A bounded read in chunks, as a stream reads: exactly the bytes asked for.
        let collected = Collected()
        let length = min(file.size, 3 * NASClient.chunkSize + 17)
        try await client.read(file.relativePath, offset: 0, length: length) { chunk in collected.append(chunk); return true }
        XCTAssertEqual(Int64(collected.data.count), length)

        // A download matches the file, byte for byte at the start.
        let local = FileManager.default.temporaryDirectory.appending(path: "NASClientIntegration-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: local) }
        try await client.download(file.relativePath, to: local) { _, _ in true }
        let downloaded = try Data(contentsOf: local)
        XCTAssertEqual(Int64(downloaded.count), file.size)
        XCTAssertEqual(downloaded.prefix(Int(length)), collected.data)
        await client.disconnect()
    }
}

/// Chunks arrive on AMSMB2's queue; gathered under a lock.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    func append(_ chunk: Data) { lock.withLock { storage.append(chunk) } }
    var data: Data { lock.withLock { storage } }
}
