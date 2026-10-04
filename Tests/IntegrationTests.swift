import Foundation
import Security

@main enum IntegrationTests {
    @MainActor static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "--cli" {
            exit(SecryCLI.run(Array(CommandLine.arguments.dropFirst(2))))
        }
        let service = "dev.secry.integration-test.v1"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "local-vault"]
        SecItemDelete(query as CFDictionary)
        defer { SecItemDelete(query as CFDictionary) }
        let vault = Vault()
        precondition(vault.ready && vault.bridgeReady, vault.error ?? "Vault startup failed")
        let fields = [SecretField(key: "SECRY_TEST_TOKEN", value: "test-only-quote'\"\n$HOME`id`"), SecretField(key: "EMPTY", value: "")]
        try vault.save(id: nil, name: "integration", fields: fields)
        let loaded = try KeychainVault.load()
        precondition(loaded.count == 1 && loaded[0].fields == fields, "Keychain persistence")
        let set = vault.sets[0]
        var response = await child(["list"])
        precondition(response.0 == 0 && response.1.contains("integration\tclosed\tSECRY_TEST_TOKEN, EMPTY"), "Metadata list")
        precondition(!response.1.contains(fields[0].value), "No value in list")
        response = await child(["run", "integration", "--", "/usr/bin/true"])
        precondition(response.0 != 0 && response.1.contains("Access closed"), "Closed access must fail")
        vault.grants[set.id] = Date().addingTimeInterval(60)
        // The subprocess checks exact bytes without printing the secret.
        response = await child(["run", "integration", "--", "/usr/bin/perl", "-e", "exit(($ENV{SECRY_TEST_TOKEN} eq qq{test-only-quote'\"\\n\\$HOME`id`} && $ENV{EMPTY} eq '') ? 0 : 17)"])
        precondition(response.0 == 0 && response.1.isEmpty, "Exact environment injection without output")
        response = await child(["run", "integration", "--", "/usr/bin/false"])
        precondition(response.0 == 1, "Child exit status")
        vault.grants[set.id] = Date().addingTimeInterval(-1)
        response = await child(["run", "integration", "--", "/usr/bin/true"])
        precondition(response.0 != 0, "Expired grant")
        vault.grants[set.id] = Date().addingTimeInterval(60)
        try vault.save(id: set.id, name: set.name, fields: fields)
        response = await child(["run", "integration", "--", "/usr/bin/true"])
        precondition(response.0 != 0, "Editing revokes access")
        vault.delete(set)
        let empty = try KeychainVault.load()
        precondition(empty.isEmpty, "Deletion persisted")
        print("Passed 9 integration checks: Keychain, list, closed access, exact injection, child exit, expiry, edit revocation, deletion, no value output")
    }
    static func child(_ arguments: [String]) async -> (Int32, String) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--cli"] + arguments
            let pipe = Pipe()
            process.standardOutput = pipe; process.standardError = pipe
            do { try process.run() } catch { return (Int32(-1), "Could not launch test subprocess") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
