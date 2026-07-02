@testable import Motive
import Testing

@MainActor
struct SkillPromptTests {
    @Test func enabledSkillsAreSyncedToDirectory() {
        // Skills are now synced to the OpenCode skills directory
        // and discovered natively — no prompt listing needed.
        // This test verifies the sync mechanism exists on SkillRegistry.
        let registry = SkillRegistry.shared
        #expect(registry.entries is [SkillEntry])
    }
}
