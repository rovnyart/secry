import Foundation
import Darwin

struct BridgeRequest: Codable { var action: String; var name: String? }
struct SetInfo: Codable { var name: String; var keys: [String]; var available: Bool }
struct BridgeResponse: Codable {
    var error: String? = nil
    var sets: [SetInfo]? = nil
    var fields: [SecretField]? = nil
}

enum Wire {
    static var directory: String { NSHomeDirectory() + "/.local/share/secry" }
    static var path: String { directory + "/bridge.sock" }

    static func address() throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw SecryError("Home path is too long for the local bridge.") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
    static func socketFD() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SecryError("Could not create local socket.") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }
    static func write<T: Encodable>(_ object: T, to fd: Int32) throws {
        var data = try JSONEncoder().encode(object); data.append(10)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw SecryError("Local bridge write failed.") }
                offset += n
            }
        }
    }
    static func read<T: Decodable>(_ type: T.Type, from fd: Int32) throws -> T {
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count < 2_097_152 {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw SecryError("Local bridge disconnected or timed out.") }
            if let end = buffer[..<n].firstIndex(of: 10) {
                data.append(contentsOf: buffer[..<end])
                return try JSONDecoder().decode(type, from: data)
            }
            data.append(contentsOf: buffer[..<n])
        }
        throw SecryError("Local bridge message is too large.")
    }
    static func request(_ request: BridgeRequest) throws -> BridgeResponse {
        let fd = try socketFD(); defer { close(fd) }
        var address = try address()
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard status == 0 else { throw SecryError("Open the secry menu bar app first.") }
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw SecryError("Unexpected bridge owner.") }
        try write(request, to: fd)
        let response = try read(BridgeResponse.self, from: fd)
        if let error = response.error { throw SecryError(error) }
        return response
    }
}

final class LocalBridge {
    private let fd: Int32
    private let lock: Int32
    init(handler: @escaping @MainActor (BridgeRequest) -> BridgeResponse) throws {
        try FileManager.default.createDirectory(atPath: Wire.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(Wire.directory, &info) == 0, info.st_uid == getuid(),
              (info.st_mode & S_IFMT) == S_IFDIR else { throw SecryError("Unsafe local bridge directory.") }
        guard chmod(Wire.directory, 0o700) == 0 else { throw SecryError("Cannot secure local bridge directory.") }
        lock = open(Wire.directory + "/bridge.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw SecryError("Cannot lock the local bridge.") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { close(lock); throw SecryError("Another secry instance is already running.") }
        do { fd = try Wire.socketFD() } catch { close(lock); throw error }
        do {
            var address = try Wire.address()
            unlink(Wire.path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, chmod(Wire.path, 0o600) == 0, listen(fd, 8) == 0 else {
                throw SecryError("Could not start the local bridge.")
            }
        } catch { close(fd); close(lock); throw error }
        let listener = fd
        DispatchQueue.global(qos: .utility).async {
            while true {
                let client = accept(listener, nil, nil)
                if client < 0 { if errno == EINTR { continue }; return }
                defer { close(client) }
                _ = fcntl(client, F_SETFD, FD_CLOEXEC)
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var one: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                var uid: uid_t = 0; var gid: gid_t = 0
                guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { continue }
                do {
                    let request = try Wire.read(BridgeRequest.self, from: client)
                    let response = DispatchQueue.main.sync { handler(request) }
                    try Wire.write(response, to: client)
                } catch {
                    try? Wire.write(BridgeResponse(error: "Invalid local bridge request."), to: client)
                }
            }
        }
    }
}

enum SecryCLI {
    static func run(_ arguments: [String]) -> Int32 {
        do {
            guard let action = arguments.first, action != "help", action != "--help" else {
                print("secry list\nsecry run <set> -- <command> [args...]\n\nEnable access in the secry menu bar app before running a command.")
                return 0
            }
            if action == "list" {
                let response = try Wire.request(BridgeRequest(action: "list"))
                for set in response.sets ?? [] {
                    print("\(set.name)\t\(set.available ? "available" : "closed")\t\(set.keys.joined(separator: ", "))")
                }
                return 0
            }
            guard action == "run", arguments.count >= 4, arguments[2] == "--" else {
                throw SecryError("Usage: secry run <set> -- <command> [args...]")
            }
            let response = try Wire.request(BridgeRequest(action: "run", name: arguments[1]))
            for field in response.fields ?? [] {
                guard SecretParser.validKey(field.key), !field.value.utf8.contains(0), setenv(field.key, field.value, 1) == 0 else {
                    throw SecryError("Could not prepare the command environment.")
                }
            }
            let command = Array(arguments.dropFirst(3))
            let pointers = command.map { strdup($0) } + [nil]
            defer { pointers.forEach { free($0) } }
            pointers.withUnsafeBufferPointer { _ = execvp(command[0], $0.baseAddress!) }
            throw SecryError("Could not launch the command (errno \(errno)).")
        } catch {
            FileHandle.standardError.write(Data("secry: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
