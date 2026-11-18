import Foundation
import XCTest
@testable import SnapboardCore

final class ItemLibraryTests: XCTestCase {
    func testSearchIncludesTitleTagsAndTarget() {
        let item = LibraryItem(kind: .link, title: "Research notes", target: "https://example.com/paper", tags: ["School", "Reading"])
        XCTAssertTrue(item.matches("research school"))
        XCTAssertTrue(item.matches("example paper"))
        XCTAssertTrue(item.matches("reading"))
        XCTAssertFalse(item.matches("finance"))
        XCTAssertEqual(LibraryItem.normalizedTags([" School ", "school", "", "Reading"]), ["School", "Reading"])
    }

    func testExportImportRoundTripAndNonDestructiveMerge() throws {
        let existing = LibraryItem(kind: .folder, title: "Files", target: "/Users/test/Documents")
        let incoming = LibraryItem(kind: .link, title: "A page", target: "https://example.org", tags: ["work"])
        let group = LauncherGroup(name: "Work", itemIDs: [incoming.id])
        let bytes = try LibraryArchive(items: [incoming], groups: [group]).exportData()
        let merged = try LibraryArchive.importData(bytes, items: [existing], groups: [])
        XCTAssertEqual(merged.items, [existing, incoming])
        XCTAssertEqual(merged.groups, [group])
        let repeatImport = try LibraryArchive.importData(bytes, items: merged.items, groups: merged.groups)
        XCTAssertEqual(repeatImport.items, merged.items)
        XCTAssertEqual(repeatImport.groups, merged.groups)
    }

    func testMalformedArchiveCannotReplaceExistingData() throws {
        let existing = LibraryItem(kind: .link, title: "Keep", target: "https://example.com")
        let malformed = Data("{\"version\":1,\"items\":[{\"not\":\"an item\"}],\"groups\":[]}".utf8)
        XCTAssertThrowsError(try LibraryArchive.importData(malformed, items: [existing], groups: []))
        let invalid = LibraryArchive(items: [LibraryItem(kind: .link, title: "Bad", target: "javascript:alert(1)")], groups: [])
        XCTAssertThrowsError(try invalid.merged(into: [existing], groups: []))
        let missing = LibraryArchive(items: [], groups: [LauncherGroup(name: "Broken", itemIDs: [UUID()])])
        XCTAssertThrowsError(try missing.merged(into: [existing], groups: []))
    }

    func testLegacyWorkspaceItemsSurfaceWithoutDuplication() {
        let link = WorkspaceItem(kind: .link, title: "Page", target: "https://example.com")
        let first = Workspace(name: "Study", items: [link])
        let second = Workspace(name: "Writing", items: [link])
        let once = LibraryItem.addingLegacyWorkspaceItems(from: [first, second], to: [])
        XCTAssertEqual(once.count, 1)
        XCTAssertEqual(Set(once[0].workspaceIDs), Set([first.id, second.id]))
        XCTAssertEqual(LibraryItem.addingLegacyWorkspaceItems(from: [first, second], to: once), once)
    }

    func testImportHTMLBookmarksSkipsInvalidAndDuplicates() {
        let existing = [LibraryItem(kind: .link, title: "Docs", target: "https://example.com/docs")]
        let html = """
        <DL><p>
            <DT><A HREF="https://example.com/docs">Docs Dup</A>
            <DT><A HREF="https://swift.org/?a=1&amp;b=2">Swift &amp; More</A>
            <DT><A HREF="javascript:alert(1)">Bad Script</A>
            <DT><A HREF="https://apple.com"></A>
        </DL><p>
        """
        let merged = LibraryArchive.importHTMLBookmarks(html, into: existing)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[1].title, "Swift & More")
        XCTAssertEqual(merged[1].target, "https://swift.org/?a=1&b=2")
        XCTAssertEqual(merged[2].title, "apple.com")
    }
}
