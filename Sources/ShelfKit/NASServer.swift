import Foundation

/// An SMB share on a NAS or file server. The password lives in the Keychain, keyed by `id`.
///
/// Persisted inside each app's library file, so its coding keys are its property names and
/// must not change.
public struct NASServer: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: Int = 445
    public var share: String
    /// Folder inside the share to treat as the library root ("downloads/books"). Empty = share root.
    public var path: String
    public var username: String
    public var domain: String = ""
    public var addedAt: Date

    public init(id: UUID, name: String, host: String, port: Int = 445, share: String, path: String,
                username: String, domain: String = "", addedAt: Date) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.share = share
        self.path = path
        self.username = username
        self.domain = domain
        self.addedAt = addedAt
    }

    public var displayLocation: String {
        var location = "smb://\(host)"
        if port != 445 { location += ":\(port)" }
        location += "/\(share)"
        if !path.isEmpty { location += "/\(path)" }
        return location
    }

    /// A port as typed into a form: 445 when the field is empty, nil when it isn't a port.
    public static func port(from text: String) -> Int? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return 445 }
        return Int(typed).flatMap { (1...65535).contains($0) ? $0 : nil }
    }

    /// Joins the library root with a path relative to it, SMB style.
    public func remotePath(for relativePath: String) -> String {
        [path, relativePath].filter { !$0.isEmpty }.joined(separator: "/")
    }
}
