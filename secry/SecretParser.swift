import Foundation

struct SecretField: Codable, Equatable, Identifiable {
    var key: String
    var value: String
    var id: String { key }
}

struct SecryError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum SecretParser {
    static func validKey(_ key: String) -> Bool {
        key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    static func parse(_ input: String, textMode: Bool = false) throws -> [SecretField] {
        guard !input.utf8.contains(0) else { throw SecryError("NUL characters are not supported.") }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecryError("Paste a secret to get started.")
        }
        guard input.utf8.count <= 262_144 else { throw SecryError("Keep each set under 256 KB.") }
        if textMode { return [SecretField(key: "SECRET", value: input)] }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  !object.isEmpty else { throw SecryError("Use a JSON object with string values, or switch to Text.") }
            return try object.keys.sorted().map { key in
                guard validKey(key), let value = object[key] as? String, !value.utf8.contains(0) else {
                    throw SecryError("JSON keys must be environment names and values must be strings.")
                }
                return SecretField(key: key, value: value)
            }
        }
        let lines = input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var fields: [SecretField] = []
        var seen = Set<String>()
        var index = 0
        while index < lines.count {
            var line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") || line.hasPrefix("export\t") {
                line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            guard let equals = line.firstIndex(of: "=") else {
                throw SecryError("Line \(index): expected KEY=value. For a note or token, choose Text.")
            }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            guard validKey(key) else { throw SecryError("Line \(index): invalid environment variable name.") }
            guard seen.insert(key).inserted else { throw SecryError("Duplicate variable: \(key). Keep one value per key.") }
            let raw = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            var value = ""
            if let quote = raw.first, quote == "\"" || quote == "'" {
                var remaining = Array(raw.dropFirst())
                var cursor = 0
                var closed = false
                while !closed {
                    if cursor >= remaining.count {
                        guard index < lines.count else { throw SecryError("Unclosed quote for \(key).") }
                        value += "\n"
                        remaining = Array(lines[index]); index += 1; cursor = 0
                        continue
                    }
                    let c = remaining[cursor]; cursor += 1
                    if c == quote {
                        let tail = String(remaining[cursor...]).trimmingCharacters(in: .whitespaces)
                        guard tail.isEmpty || tail.hasPrefix("#") else { throw SecryError("Unexpected text after \(key).") }
                        closed = true
                    } else if c == "\\" && quote == "\"" && cursor < remaining.count {
                        let next = remaining[cursor]; cursor += 1
                        switch next {
                        case "n": value += "\n"
                        case "r": value += "\r"
                        case "t": value += "\t"
                        case "\\", "\"", "$", "`": value.append(next)
                        default: value.append("\\"); value.append(next)
                        }
                    } else { value.append(c) }
                }
            } else {
                // A # begins a comment only after whitespace. Never evaluate shell expressions.
                let chars = Array(raw)
                let comment = chars.indices.first { chars[$0] == "#" && ($0 == 0 || chars[$0 - 1].isWhitespace) }
                value = String(chars[..<(comment ?? chars.count)]).trimmingCharacters(in: .whitespaces)
            }
            fields.append(SecretField(key: key, value: value))
        }
        guard !fields.isEmpty else { throw SecryError("No variables found.") }
        return fields
    }

    static func env(_ fields: [SecretField]) -> String {
        fields.map { field in
            let escaped = field.value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\(field.key)=\"\(escaped)\""
        }.joined(separator: "\n")
    }
}
