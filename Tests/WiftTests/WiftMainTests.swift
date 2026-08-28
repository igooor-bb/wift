import Testing
@testable import Wift

@Test func `preserves script arguments`() throws {
    let command = try WiftCommand.parse(["script.swift", "one", "--two", "three"])

    #expect(command.scriptPath == "script.swift")
    #expect(command.scriptArguments == ["one", "--two", "three"])
}
