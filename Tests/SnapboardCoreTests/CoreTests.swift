import CoreGraphics
import XCTest
@testable import SnapboardCore

final class LayoutTests: XCTestCase {
    func testPresetsMakeTheRightNumberOfZones() {
        XCTAssertEqual(Preset.full.layout.zoneCount, 1)
        XCTAssertEqual(Preset.halves.layout.zoneCount, 2)
        XCTAssertEqual(Preset.thirds.layout.zoneCount, 3)
        XCTAssertEqual(Preset.bigLeftTwoRight.layout.zoneCount, 3)
        XCTAssertEqual(Preset.quarters.layout.zoneCount, 4)
    }

    func testZonesCoverTheScreenWithoutGaps() {
        for preset in Preset.allCases {
            let area = preset.layout.zones().reduce(0) { $0 + $1.width * $1.height }
            XCTAssertEqual(area, 1, accuracy: 0.0001, preset.rawValue)
        }
    }

    func testBigLeftTwoRightIsLeftThenTopRightThenBottomRight() {
        let z = Preset.bigLeftTwoRight.layout.zones()
        XCTAssertEqual(z[0], CGRect(x: 0, y: 0, width: 0.6, height: 1))
        XCTAssertEqual(z[1].minY, 0, accuracy: 0.0001)
        XCTAssertEqual(z[2].minY, 0.5, accuracy: 0.0001)
    }

    func testZoneAtPointIncludingTheFarEdges() {
        let halves = Preset.halves.layout
        XCTAssertEqual(halves.zoneIndex(at: CGPoint(x: 0.2, y: 0.5)), 0)
        XCTAssertEqual(halves.zoneIndex(at: CGPoint(x: 0.7, y: 0.5)), 1)
        XCTAssertEqual(halves.zoneIndex(at: CGPoint(x: 1, y: 1)), 1)
        XCTAssertNil(halves.zoneIndex(at: CGPoint(x: 1.2, y: 0.5)))
    }

    func testSplittingAndRemovingAZone() {
        let split = Preset.halves.layout.splitting(zone: 1, axis: .stacked)
        XCTAssertEqual(split.zoneCount, 3)
        XCTAssertEqual(split, Preset.bigLeftTwoRight.layout.settingRatio(0.5, at: []))
        let back = split.removing(zone: 2)
        XCTAssertEqual(back, Preset.halves.layout)
        XCTAssertEqual(LayoutNode.zone.removing(zone: 0), .zone, "the last zone stays")
    }

    func testSplittingStopsAtTheZoneLimit() {
        var layout = LayoutNode.zone
        for _ in 0..<20 { layout = layout.splitting(zone: 0, axis: .sideBySide) }
        XCTAssertEqual(layout.zoneCount, LayoutLimits.maxZones)
    }

    func testDraggingADividerClampsTheRatio() {
        let layout = Preset.halves.layout
        let divider = layout.dividers()[0]
        XCTAssertEqual(divider.line.minX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(LayoutNode.ratio(for: divider, draggedTo: CGPoint(x: 0.7, y: 0.3)), 0.7, accuracy: 0.0001)
        XCTAssertEqual(LayoutNode.ratio(for: divider, draggedTo: CGPoint(x: -1, y: 0)), LayoutLimits.minRatio)
        let moved = layout.settingRatio(0.99, at: divider.path)
        XCTAssertEqual(moved.zones()[0].width, CGFloat(LayoutLimits.maxRatio), accuracy: 0.0001)
    }

    func testNestedDividerRatioIsRelativeToItsOwnSplit() {
        let layout = Preset.bigLeftTwoRight.layout
        let inner = layout.dividers().first { $0.path == [1] }!
        XCTAssertEqual(inner.bounds.minX, 0.6, accuracy: 0.0001)
        XCTAssertEqual(LayoutNode.ratio(for: inner, draggedTo: CGPoint(x: 0.8, y: 0.25)), 0.25, accuracy: 0.0001)
    }

    func testLayoutsSurviveSavingAndLoading() throws {
        var state = SavedState()
        state.layouts["Built-in 1512x982"] = Preset.quarters.layout
        state.widgets["clock"] = CodableRect(CGRect(x: 10, y: 20, width: 200, height: 100))
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SavedState.self, from: data), state)
    }

    func testAnOlderSettingsFileStillLoads() throws {
        let old = #"{"layouts":{},"snappingOn":false}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(SavedState.self, from: old)
        XCTAssertFalse(state.snappingOn)
        XCTAssertTrue(state.shortcutsOn)
        XCTAssertEqual(state.layout(for: "anything"), Preset.halves.layout)
    }
}

final class ScreenMathTests: XCTestCase {
    // A 1440x900 main screen with a 25pt menu bar: usable area starts at y 0, height 875.
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testLeftHalfOnTheScreen() {
        let r = ScreenMath.appKitRect(forUnit: CGRect(x: 0, y: 0, width: 0.5, height: 1), in: visible)
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 720, height: 875))
    }

    func testTopZoneIsAtTheTopInAppKit() {
        let r = ScreenMath.appKitRect(forUnit: CGRect(x: 0, y: 0, width: 1, height: 0.5), in: visible)
        XCTAssertEqual(r.maxY, 875, accuracy: 1)
        XCTAssertEqual(r.minY, 437, accuracy: 1)
    }

    func testAccessibilityFlipsAgainstTheMainScreen() {
        let appKit = CGRect(x: 100, y: 0, width: 500, height: 400)
        let ax = ScreenMath.accessibilityRect(forAppKit: appKit, mainScreenHeight: 900)
        XCTAssertEqual(ax, CGRect(x: 100, y: 500, width: 500, height: 400))
        XCTAssertEqual(ScreenMath.appKitRect(forAccessibility: ax, mainScreenHeight: 900), appKit)
    }

    func testUnitPointRoundTrip() {
        let p = ScreenMath.unitPoint(forAppKit: CGPoint(x: 360, y: 875), in: visible)
        XCTAssertEqual(p.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(p.y, 0, accuracy: 0.0001)
    }

    func testClampKeepsThingsOnScreen() {
        let off = CGRect(x: 1400, y: -50, width: 200, height: 100)
        XCTAssertEqual(ScreenMath.clamp(off, into: visible), CGRect(x: 1240, y: 0, width: 200, height: 100))
    }

    func testWidgetGridSnapsToTheNearestSpotAndStaysOnScreen() {
        let grid = WidgetGrid(cell: 8, margin: 16)
        let dropped = CGRect(x: 21, y: 600, width: 160, height: 80)
        let s = grid.snap(dropped, in: visible)
        XCTAssertEqual(s.minX, 24)
        XCTAssertEqual(s.size, dropped.size)
        XCTAssertEqual((875 - 16 - s.maxY).truncatingRemainder(dividingBy: 8), 0)
        let offScreen = grid.snap(CGRect(x: -500, y: 2000, width: 160, height: 80), in: visible)
        XCTAssertEqual(offScreen.minX, 16)
        XCTAssertEqual(offScreen.maxY, 875 - 16)
    }
}

final class FeedTests: XCTestCase {
    func testDecodesTheLifeboardFeedWithStringOrNumberIds() throws {
        let json = #"""
        {"ok":true,"day":"2026-10-04","time":"09:30",
         "tasks":{"count":2,"items":[{"id":"12","title":"Essay draft","doing":false},{"id":7,"title":"Call clinic","doing":true}]},
         "meds":{"last":{"name":"Morning med","at":"8:10 am","agoMin":80},"next":{"name":"Morning med","at":"2 pm","late":false}},
         "weather":{"icon":"☁","label":"Cloudy","min":7,"max":null,"rain":40}}
        """#.data(using: .utf8)!
        let feed = try Feed.decode(json)
        XCTAssertEqual(feed.tasks?.items.map(\.id.value), ["12", "7"])
        XCTAssertEqual(FeedText.tasksHeadline(feed.tasks), "2 tasks due today")
        XCTAssertEqual(FeedText.medsLine(feed.meds), "Last: Morning med at 8:10 am · Next: Morning med at 2 pm")
        XCTAssertEqual(FeedText.weatherLine(feed.weather), "☁ Cloudy · low 7° · 40% rain")
    }

    func testMissingPartsSayNotAvailable() throws {
        let feed = try Feed.decode(#"{"ok":true,"tasks":null,"meds":null,"weather":null}"#.data(using: .utf8)!)
        XCTAssertEqual(FeedText.tasksHeadline(feed.tasks), "Tasks not available")
        XCTAssertEqual(FeedText.medsLine(feed.meds), "Medication times not available")
        XCTAssertEqual(FeedText.weatherLine(feed.weather), "No forecast right now")
    }

    func testAnErrorReplyDecodes() throws {
        let feed = try Feed.decode(#"{"ok":false,"error":"Wrong or missing widget token."}"#.data(using: .utf8)!)
        XCTAssertFalse(feed.ok)
        XCTAssertEqual(feed.error, "Wrong or missing widget token.")
    }

    func testFeedURLFromWhateverIsTyped() {
        XCTAssertEqual(feedURL(from: "lifeboard.vercel.app")?.absoluteString, "https://lifeboard.vercel.app/api/widgets")
        XCTAssertEqual(feedURL(from: " https://x.app/today?a=1 ")?.absoluteString, "https://x.app/api/widgets")
        XCTAssertNil(feedURL(from: ""))
        XCTAssertNil(feedURL(from: "https://"))
    }

    func testScreenKeyIncludesTheSize() {
        XCTAssertEqual(screenKey(name: "Built-in Retina Display", size: CGSize(width: 1512, height: 982)),
                       "Built-in Retina Display 1512x982")
    }
}
