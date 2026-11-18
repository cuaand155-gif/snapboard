import Foundation

/// A reusable item can appear in any number of workspaces or launcher groups.
public struct LibraryItem: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable, CaseIterable { case application, link, folder, action }
    public var id: UUID
    public var kind: Kind
    public var title: String
    public var target: String
    public var tags: [String]
    public var workspaceIDs: [UUID]

    public init(id: UUID = UUID(), kind: Kind, title: String, target: String,
                tags: [String] = [], workspaceIDs: [UUID] = []) {
        self.id = id
        self.kind = kind
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = Self.normalizedTags(tags)
        self.workspaceIDs = Array(Set(workspaceIDs)).sorted { $0.uuidString < $1.uuidString }
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }
    }

    public var isValid: Bool {
        guard !title.isEmpty, !target.isEmpty else { return false }
        switch kind {
        case .link:
            guard let url = URL(string: target), let scheme = url.scheme?.lowercased() else { return false }
            return ["http", "https"].contains(scheme) && url.host?.isEmpty == false
        case .application: return target.hasSuffix(".app") && target.hasPrefix("/")
        case .folder: return target.hasPrefix("/")
        case .action: return UUID(uuidString: target) != nil
        }
    }

    public func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = ([title, target] + tags).joined(separator: " ")
        return words.allSatisfy { haystack.localizedStandardContains($0) }
    }

    /// Surface old workspace app/link entries in the shared collection without changing
    /// the original workspace records. Calling this repeatedly is idempotent.
    public static func addingLegacyWorkspaceItems(from workspaces: [Workspace], to current: [LibraryItem]) -> [LibraryItem] {
        var result = current
        for workspace in workspaces {
            for old in workspace.items {
                let kind: Kind = old.kind == .application ? .application : .link
                if let index = result.firstIndex(where: { $0.kind == kind && $0.target == old.target }) {
                    if !result[index].workspaceIDs.contains(workspace.id) {
                        result[index].workspaceIDs.append(workspace.id)
                    }
                } else {
                    let preferredID = result.contains(where: { $0.id == old.id }) ? UUID() : old.id
                    result.append(LibraryItem(id: preferredID, kind: kind, title: old.title,
                                              target: old.target, workspaceIDs: [workspace.id]))
                }
            }
        }
        return result
    }
}

public struct LauncherGroup: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var itemIDs: [UUID]
    public init(id: UUID = UUID(), name: String, itemIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.itemIDs = itemIDs
    }
}

public enum LibraryImportError: Error, Equatable {
    case unsupportedVersion
    case invalidItem
    case invalidGroup
}

/// Import is all-or-nothing. Existing records win on UUID collisions.
public struct LibraryArchive: Codable, Equatable {
    public var version: Int
    public var items: [LibraryItem]
    public var groups: [LauncherGroup]
    public init(items: [LibraryItem], groups: [LauncherGroup]) {
        version = 1
        self.items = items
        self.groups = groups
    }

    public func merged(into existingItems: [LibraryItem], groups existingGroups: [LauncherGroup]) throws
        -> (items: [LibraryItem], groups: [LauncherGroup]) {
        guard version == 1 else { throw LibraryImportError.unsupportedVersion }
        guard items.allSatisfy(\.isValid), Set(items.map(\.id)).count == items.count else {
            throw LibraryImportError.invalidItem
        }
        guard groups.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(groups.map(\.id)).count == groups.count,
              groups.allSatisfy({ Set($0.itemIDs).count == $0.itemIDs.count }) else {
            throw LibraryImportError.invalidGroup
        }
        let knownIDs = Set(existingItems.map(\.id)).union(items.map(\.id))
        guard groups.allSatisfy({ $0.itemIDs.allSatisfy(knownIDs.contains) }) else {
            throw LibraryImportError.invalidGroup
        }
        let currentItems = Set(existingItems.map(\.id))
        let currentGroups = Set(existingGroups.map(\.id))
        return (existingItems + items.filter { !currentItems.contains($0.id) },
                existingGroups + groups.filter { !currentGroups.contains($0.id) })
    }

    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func importData(_ data: Data, items: [LibraryItem], groups: [LauncherGroup]) throws
        -> (items: [LibraryItem], groups: [LauncherGroup]) {
        try JSONDecoder().decode(Self.self, from: data).merged(into: items, groups: groups)
    }

    /// Parses Netscape HTML bookmark exports (Safari, Chrome, Firefox) into valid, non-duplicate links.
    public static func importHTMLBookmarks(_ html: String, into existingItems: [LibraryItem] = []) -> [LibraryItem] {
        let pattern = #"(?is)<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return existingItems }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var seenTargets = Set(existingItems.filter { $0.kind == .link }.map(\.target))
        var result = existingItems
        for match in matches {
            let hrefRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard hrefRange.location != NSNotFound else { continue }
            let rawHref = decodeHTMLEntities(nsHTML.substring(with: hrefRange))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawTitle = nsHTML.substring(with: match.range(at: 3))
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let decodedTitle = decodeHTMLEntities(rawTitle)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let title = decodedTitle.isEmpty ? (URL(string: rawHref)?.host ?? "") : decodedTitle
            let item = LibraryItem(kind: .link, title: title, target: rawHref)
            guard item.isValid, seenTargets.insert(item.target).inserted else { continue }
            result.append(item)
        }
        return result
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
