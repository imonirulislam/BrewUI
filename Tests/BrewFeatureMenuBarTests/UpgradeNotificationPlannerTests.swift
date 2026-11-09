import BrewCore
@testable import BrewFeatureMenuBar
import Testing

struct UpgradeNotificationPlannerTests {
    @Test func `the first check records the inventory without notifying`() {
        let plan = UpgradeNotificationPlanner.plan(outdatedNames: ["git", "wget"], previouslySeen: nil)

        #expect(plan.newNames.isEmpty)
        #expect(plan.seen == ["git", "wget"])
    }

    @Test func `packages that became outdated since the last check are announced`() {
        let plan = UpgradeNotificationPlanner.plan(outdatedNames: ["git", "node", "wget"], previouslySeen: ["git"])

        #expect(plan.newNames == ["node", "wget"])
        #expect(plan.seen == ["git", "node", "wget"])
    }

    @Test func `an unchanged inventory stays quiet`() {
        let plan = UpgradeNotificationPlanner.plan(outdatedNames: ["git"], previouslySeen: ["git"])

        #expect(plan.newNames.isEmpty)
    }

    @Test func `upgraded packages drop out so a later release is announced again`() {
        let afterUpgrade = UpgradeNotificationPlanner.plan(outdatedNames: [], previouslySeen: ["git"])
        let laterRelease = UpgradeNotificationPlanner.plan(outdatedNames: ["git"], previouslySeen: afterUpgrade.seen)

        #expect(laterRelease.newNames == ["git"])
    }

    @Test(arguments: [
        (["node"], "node can be upgraded"),
        (["node", "wget"], "node and wget can be upgraded"),
        (["git", "node", "wget"], "git, node and 1 more can be upgraded"),
    ])
    func `the notification names the new packages briefly`(names: [String], expected: String) {
        #expect(UpgradeNotificationPlanner.body(for: names) == expected)
    }
}
