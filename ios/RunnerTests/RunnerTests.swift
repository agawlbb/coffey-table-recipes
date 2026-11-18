import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
    func testDinnerUsesHouseholdDateAndIncludesEveryDish() throws {
        let plan: [String: Any] = ["today": "2026-11-18", "entries": [
            ["plan_date": "2026-11-18", "title": "Chicken"],
            ["plan_date": "2026-11-18", "title": "Rice"],
            ["plan_date": "2026-11-19", "title": "Soup"]
        ]]
        XCTAssertEqual(try CTRDinnerResponse.text(plan: plan, tomorrow: false), "For dinner tonight: Chicken and Rice.")
        XCTAssertEqual(try CTRDinnerResponse.text(plan: plan, tomorrow: true), "For dinner tomorrow night: Soup.")
    }

    func testTomorrowCrossesYearAndLeapDay() throws {
        for (today, tomorrow) in [("2026-12-31", "2027-01-01"), ("2028-02-28", "2028-02-29")] {
            let plan: [String: Any] = ["today": today, "entries": [["plan_date": tomorrow, "title": "Pizza"]]]
            XCTAssertEqual(try CTRDinnerResponse.text(plan: plan, tomorrow: true), "For dinner tomorrow night: Pizza.")
        }
    }

    func testEmptyPlanAndMalformedDataAreDifferent() throws {
        XCTAssertEqual(try CTRDinnerResponse.text(plan: ["today": "2026-11-18", "entries": []], tomorrow: false), "Nothing is planned for dinner tonight.")
        XCTAssertThrowsError(try CTRDinnerResponse.text(plan: [:], tomorrow: false))
        XCTAssertThrowsError(try CTRDinnerResponse.text(plan: ["today": "2026-02-30", "entries": []], tomorrow: true))
        XCTAssertThrowsError(try CTRDinnerResponse.text(plan: ["today": "2026-11-18", "entries": [["plan_date": "2026-11-18"]]], tomorrow: false))
    }

    @available(iOS 16.0, *)
    @MainActor
    func testHouseholdSelectionDoesNotGuessAcrossHouseholds() async throws {
        let choices = [(id: "1", label: "Home"), (id: "2", label: "Family")]
        let selected = try await CTRSiriHouseholds.select(choices, value: nil) { labels in
            XCTAssertEqual(labels, ["Home", "Family"])
            return "Family"
        }
        XCTAssertEqual(selected, "2")
        do {
            _ = try await CTRSiriHouseholds.select(choices, value: "Removed") { _ in
                XCTFail("A stale explicit household must not be replaced silently")
                return "Home"
            }
            XCTFail("Expected unavailable household error")
        } catch { }
    }

    @MainActor
    func testDuplicateHouseholdNamesRemainDistinct() throws {
        let snapshot: [String: Any] = ["account": ["households": [
            ["id": "1", "name": "Home"], ["id": "2", "name": "Home"]
        ]]]
        XCTAssertEqual(try SiriConnection.households(snapshot).map(\.label), ["Home (1)", "Home (2)"])
        XCTAssertThrowsError(try SiriConnection.households([:]))
    }
}
