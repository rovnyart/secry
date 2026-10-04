import Foundation
import Security
import SwiftUI
import AppKit

struct SecretSet: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var fields: [SecretField]
    var updatedAt: Date = Date()
}

enum KeychainVault {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.secry.vault.v1",
        kSecAttrAccount as String: "local-vault"
    ]
    static func load() throws -> [SecretSet] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecryError("Could not open Keychain (\(status)). Unlock your login keychain and reopen secry.")
        }
        return try JSONDecoder().decode([SecretSet].self, from: data)
    }
    static func save(_ sets: [SecretSet]) throws {
        let data = try JSONEncoder().encode(sets)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(request as CFDictionary, nil)
            guard added == errSecSuccess else { throw SecryError("Keychain save failed (\(added)).") }
        } else if status != errSecSuccess { throw SecryError("Keychain save failed (\(status)).") }
    }
}

@MainActor @Observable final class Vault {
    var sets: [SecretSet] = []
    var grants: [UUID: Date] = [:]
    var error: String?
    var notice: String?
    var ready = false
    var bridgeReady = false
    var lastUse: [UUID: Date] = [:]
    private var bridge: LocalBridge?
    private var isPreview = false

    #if DEBUG
    init(previewSets: [SecretSet]) {
        sets = previewSets; ready = true; bridgeReady = true; isPreview = true
    }
    #endif

    init() {
        do { sets = try KeychainVault.load(); ready = true }
        catch { self.error = error.localizedDescription }
        do {
            bridge = try LocalBridge { [weak self] request in
                self?.handle(request) ?? BridgeResponse(error: "Vault unavailable.")
            }
            bridgeReady = true
        } catch { self.error = error.localizedDescription; ready = false }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.grants.removeAll() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.grants.removeAll() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.grants.removeAll() }
        }
    }

    func save(id: UUID?, name: String, fields: [SecretField]) throws {
        guard ready else { throw SecryError("Vault is unavailable. Reopen secry to retry.") }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard name.range(of: "^[a-z0-9][a-z0-9_-]{0,63}$", options: .regularExpression) != nil else {
            throw SecryError("Use 1–64 letters, numbers, hyphens or underscores for the set name.")
        }
        guard !sets.contains(where: { $0.name == name && $0.id != id }) else { throw SecryError("That set name already exists.") }
        var next = sets
        if let id, let i = next.firstIndex(where: { $0.id == id }) {
            next[i].name = name; next[i].fields = fields; next[i].updatedAt = Date()
        } else { next.append(SecretSet(name: name, fields: fields)) }
        if !isPreview { try KeychainVault.save(next) }
        sets = next.sorted { $0.name < $1.name }
        if let id { grants[id] = nil }
    }

    @discardableResult
    func delete(_ set: SecretSet) -> Bool {
        guard ready else { error = "Vault is unavailable. Reopen secry to retry."; return false }
        do {
            let next = sets.filter { $0.id != set.id }
            if !isPreview { try KeychainVault.save(next) }
            sets = next; grants[set.id] = nil; lastUse[set.id] = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func copy(_ value: String, sensitive: Bool = true) {
        let board = NSPasteboard.general
        board.clearContents(); board.setString(value, forType: .string)
        let count = board.changeCount
        notice = sensitive ? "Copied · clears in 30 seconds" : "Instructions copied"
        let currentNotice = notice
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.notice == currentNotice { self?.notice = nil }
        }
        if sensitive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if board.changeCount == count { board.clearContents() }
            }
        }
    }

    func agentInstruction(_ set: SecretSet) {
        let executable = Bundle.main.executablePath ?? "secry"
        let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        copy("Use the local secry set '\(set.name)'. Run commands with:\n\(quoted) --cli run \(set.name) -- <command> [args...]\nThe variables are injected into the child process. Do not print, log, or echo secret values. Access must be enabled in the secry menu bar app.", sensitive: false)
    }

    private func handle(_ request: BridgeRequest) -> BridgeResponse {
        guard ready else { return BridgeResponse(error: "Vault unavailable.") }
        if request.action == "list" {
            return BridgeResponse(sets: sets.map { SetInfo(name: $0.name, keys: $0.fields.map(\.key), available: (grants[$0.id] ?? .distantPast) > Date()) })
        }
        guard request.action == "run", let set = sets.first(where: { $0.name == request.name }) else {
            return BridgeResponse(error: "Unknown set or command. Use secry list.")
        }
        guard (grants[set.id] ?? .distantPast) > Date() else {
            return BridgeResponse(error: "Access closed. Open secry and allow this set for 15 minutes.")
        }
        lastUse[set.id] = Date()
        return BridgeResponse(fields: set.fields)
    }
}
