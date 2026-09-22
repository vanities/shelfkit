import Foundation

extension String {
    /// Finder-style ordering: "Chapter 2" sorts before "Chapter 10".
    public func naturallyPrecedes(_ other: String) -> Bool {
        localizedStandardCompare(other) == .orderedAscending
    }

    /// Lowercased, punctuation stripped, whitespace collapsed — for fuzzy equality.
    public var normalizedForMatching: String {
        lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Underscores → spaces, whitespace collapsed, trimmed. For folder/file names shown to people.
    public var cleanedDisplayName: String {
        replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Identity key: lowercased with every non-alphanumeric character *removed*, not replaced
    /// by a space. `normalizedForMatching` inserts word breaks, which is right for search but
    /// wrong for identity — it makes "JoJo's Bizarre Adventure" and "JoJos Bizarre Adventure"
    /// two different shelves.
    public var normalizedForIdentity: String {
        lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    public var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
