@testable import Motive
import Testing

struct SkillValidationTests {

    // MARK: - Name Validation

    @Test func validNameProducesNoWarnings() {
        let frontmatter = SkillFrontmatter(name: "valid-skill", description: "A valid skill")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "valid-skill")
        #expect(result.warnings.isEmpty)
    }

    @Test func emptyNameProducesWarning() {
        let frontmatter = SkillFrontmatter(name: "", description: "A skill")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "some-dir")
        #expect(result.warnings.contains(.nameEmpty))
    }

    @Test func uppercaseNameProducesWarning() {
        let frontmatter = SkillFrontmatter(name: "MySkill", description: "A skill")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "MySkill")
        #expect(result.warnings.contains(.nameNotLowercase))
    }

    @Test func consecutiveHyphensProducesWarning() {
        let frontmatter = SkillFrontmatter(name: "my--skill", description: "A skill")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "my--skill")
        #expect(result.warnings.contains(.nameContainsConsecutiveHyphens))
    }

    @Test func leadingHyphenProducesWarning() {
        let frontmatter = SkillFrontmatter(name: "-skill", description: "A skill")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "-skill")
        #expect(result.warnings.contains(.nameStartsWithHyphen))
    }

    @Test func trailingHyphenProducesWarning() {
        let frontmatter = SkillFrontmatter(name: "skill-", description: "A skill")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "skill-")
        #expect(result.warnings.contains(.nameEndsWithHyphen))
    }

    @Test func nameTooLongProducesWarning() {
        let longName = String(repeating: "a", count: 65)
        let frontmatter = SkillFrontmatter(name: longName, description: "A skill")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: longName)
        #expect(result.warnings.contains(.nameTooLong(65)))
    }

    @Test func nameDirectoryMismatchProducesWarning() {
        let frontmatter = SkillFrontmatter(name: "skill-a", description: "A skill")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "skill-b")
        #expect(result.warnings.contains(.nameDirectoryMismatch(expected: "skill-b", actual: "skill-a")))
    }

    // MARK: - Description Validation

    @Test func emptyDescriptionProducesWarning() {
        let frontmatter = SkillFrontmatter(name: "skill", description: "")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "skill")
        #expect(result.warnings.contains(.descriptionEmpty))
    }

    @Test func whitespaceOnlyDescriptionProducesWarning() {
        let frontmatter = SkillFrontmatter(name: "skill", description: "   ")
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "skill")
        #expect(result.warnings.contains(.descriptionEmpty))
    }

    @Test func descriptionTooLongProducesWarning() {
        let longDesc = String(repeating: "a", count: 1025)
        let frontmatter = SkillFrontmatter(name: "skill", description: longDesc)
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "skill")
        #expect(result.warnings.contains(.descriptionTooLong(1025)))
    }

    // MARK: - Compatibility Validation

    @Test func compatibilityTooLongProducesWarning() {
        let longCompat = String(repeating: "a", count: 501)
        var frontmatter = SkillFrontmatter(name: "skill", description: "desc")
        frontmatter.compatibility = longCompat
        let result = SkillValidation.validate(frontmatter: frontmatter, directoryName: "skill")
        #expect(result.warnings.contains(.compatibilityTooLong(501)))
    }

    // MARK: - Name Only Validation

    @Test func validateNameOnlyReturnsWarnings() {
        let warnings = SkillValidation.validateName("My--Skill-")
        #expect(warnings.contains(.nameNotLowercase))
        #expect(warnings.contains(.nameContainsConsecutiveHyphens))
        #expect(warnings.contains(.nameEndsWithHyphen))
    }
}
