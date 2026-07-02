@testable import Motive
import Testing

struct SkillInstallerTests {

    @Test func brewInstallBuildsCorrectCommand() async {
        let mock = MockCommandRunner()
        mock.stubbedResults["brew install gh"] = CommandResult(stdout: "done", stderr: "", exitCode: 0)

        let installer = SkillInstaller(commandRunner: mock)
        let spec = SkillInstallSpec(kind: .brew, formula: "gh")

        let result = await installer.install(spec: spec, timeoutSeconds: 10)

        #expect(result.ok == true)
        #expect(mock.runCalls.first == ["brew", "install", "gh"])
    }

    @Test func nodeInstallBuildsCorrectCommand() async {
        let mock = MockCommandRunner()
        mock.stubbedResults["npm install -g typescript"] = CommandResult(stdout: "done", stderr: "", exitCode: 0)

        let installer = SkillInstaller(commandRunner: mock)
        let spec = SkillInstallSpec(kind: .node, package: "typescript")

        let result = await installer.install(spec: spec, timeoutSeconds: 10)

        #expect(result.ok == true)
        #expect(mock.runCalls.first == ["npm", "install", "-g", "typescript"])
    }

    @Test func nodeInstallPrefersPnpmWhenAvailable() async {
        let mock = MockCommandRunner()
        mock.stubbedBinaries = ["pnpm"]
        mock.stubbedResults["pnpm add -g typescript"] = CommandResult(stdout: "done", stderr: "", exitCode: 0)

        let installer = SkillInstaller(commandRunner: mock)
        let spec = SkillInstallSpec(kind: .node, package: "typescript")

        let result = await installer.install(spec: spec, timeoutSeconds: 10)

        #expect(result.ok == true)
        #expect(mock.runCalls.first == ["pnpm", "add", "-g", "typescript"])
    }

    @Test func goInstallBuildsCorrectCommand() async {
        let mock = MockCommandRunner()
        mock.stubbedResults["go install github.com/example/tool@latest"] = CommandResult(stdout: "", stderr: "", exitCode: 0)

        let installer = SkillInstaller(commandRunner: mock)
        let spec = SkillInstallSpec(kind: .go, module: "github.com/example/tool@latest")

        let result = await installer.install(spec: spec, timeoutSeconds: 10)

        #expect(result.ok == true)
        #expect(mock.runCalls.first == ["go", "install", "github.com/example/tool@latest"])
    }

    @Test func uvInstallBuildsCorrectCommand() async {
        let mock = MockCommandRunner()
        mock.stubbedResults["uv tool install ruff"] = CommandResult(stdout: "", stderr: "", exitCode: 0)

        let installer = SkillInstaller(commandRunner: mock)
        let spec = SkillInstallSpec(kind: .uv, package: "ruff")

        let result = await installer.install(spec: spec, timeoutSeconds: 10)

        #expect(result.ok == true)
        #expect(mock.runCalls.first == ["uv", "tool", "install", "ruff"])
    }

    @Test func installFailureReturnsError() async {
        let mock = MockCommandRunner()
        mock.stubbedResults["brew install gh"] = CommandResult(stdout: "", stderr: "Error: formula not found", exitCode: 1)

        let installer = SkillInstaller(commandRunner: mock)
        let spec = SkillInstallSpec(kind: .brew, formula: "gh")

        let result = await installer.install(spec: spec, timeoutSeconds: 10)

        #expect(result.ok == false)
        #expect(result.exitCode == 1)
        #expect(result.message.contains("failed"))
    }

    @Test func missingFormulaReturnsError() async {
        let mock = MockCommandRunner()
        let installer = SkillInstaller(commandRunner: mock)
        let spec = SkillInstallSpec(kind: .brew, formula: nil)

        let result = await installer.install(spec: spec, timeoutSeconds: 10)

        #expect(result.ok == false)
        #expect(result.message.contains("Missing required field"))
    }

    @Test func missingPackageReturnsError() async {
        let mock = MockCommandRunner()
        let installer = SkillInstaller(commandRunner: mock)
        let spec = SkillInstallSpec(kind: .node, package: nil)

        let result = await installer.install(spec: spec, timeoutSeconds: 10)

        #expect(result.ok == false)
    }
}
