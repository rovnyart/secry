import Foundation

@main enum ParserTests {
    static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { fatalError(message) }; checks += 1
        }
        func rejects(_ input: String) throws {
            do { _ = try SecretParser.parse(input) } catch { checks += 1; return }
            fatalError("Expected malformed input to fail")
        }
        let fields = try SecretParser.parse("# comment\nexport FOO=abc=def\nBAR=hello # comment\nEMPTY=\nHASH=abc#def")
        try expect(fields.map(\.value) == ["abc=def", "hello", "", "abc#def"], "dotenv basics")
        try expect(SecretParser.parse("KEY=\"one\ntwo\"")[0].value == "one\ntwo", "multiline")
        try expect(SecretParser.parse("KEY='literal\\n$HOME'")[0].value == "literal\\n$HOME", "literal single quotes")
        try expect(SecretParser.parse("KEY=$(touch /tmp/never-execute)")[0].value == "$(touch /tmp/never-execute)", "no expansion")
        try expect(SecretParser.parse("{\"TOKEN\":\"abc\"}")[0].value == "abc", "JSON")
        try expect(SecretParser.parse("  private\nnote  ", textMode: true)[0].value == "  private\nnote  ", "text exact preservation")
        let tricky = [SecretField(key: "TOKEN", value: "line\n\\quotes\"' $HOME `id`\t\r# 😀")]
        try expect(SecretParser.parse(SecretParser.env(tricky)) == tricky, "export roundtrip")
        try rejects("A=1\nA=2")
        try rejects("BAD-NAME=token")
        try rejects("A=\"unterminated")
        try rejects("A='token' garbage")
        try rejects("{\"A\":123}")
        try rejects("{\"A\":{\"B\":\"C\"}}")
        try rejects("KEY=\0")
        try rejects("{\"KEY\":\"\\u0000\"}")
        try rejects("# comments only")
        try rejects("TOKEN=" + String(repeating: "x", count: 262_145))
        print("Passed \(checks) parser checks")
    }
}
