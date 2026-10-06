import Foundation

/// Wire format between the CLI and the listener: one JSON request, one JSON response,
/// over a Unix socket. The client half-closes after writing; the listener closes after
/// replying. No framing beyond EOF is needed.
struct Request: Codable {
    enum Command: String, Codable { case set, list, stop }
    var command: Command
    /// For `set`: an explicit slot (1...9), or nil for the lowest free one.
    var slot: Int?
    var text: String?
}

struct SlotEntry: Codable {
    var slot: Int
    var hotkey: String
    var text: String
}

struct Response: Codable {
    var ok: Bool
    var error: String?
    /// For `set`: where the text landed.
    var slot: Int?
    var hotkey: String?
    /// For `list`.
    var slots: [SlotEntry]?
    /// Whether the listener may post keystrokes (Accessibility). Informational only.
    var trusted: Bool?
}

/// The number of slots and the digit keys they map to.
let slotCount = 9

/// Location of the listener's socket: the per-user temp dir, which is private to the
/// user and never survives a reboot. Independent of $TMPDIR so every shell agrees.
func socketPath() -> String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let n = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
    let dir = n > 0 ? String(cString: buffer) : NSTemporaryDirectory()
    return (dir.hasSuffix("/") ? dir : dir + "/") + "ett.sock"
}

/// Builds the sockaddr for a Unix socket path.
func unixAddress(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count < capacity else { throw EttError("socket path too long: \(path)") }
    withUnsafeMutableBytes(of: &addr.sun_path) { dst in
        for (i, b) in bytes.enumerated() { dst[i] = b }
    }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return addr
}

/// Calls `body` with the address rebound to a generic sockaddr, as connect/bind want.
func withSockaddr<T>(_ addr: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    var a = addr
    return withUnsafePointer(to: &a) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

func readToEOF(_ fd: Int32) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buffer, buffer.count)
        if n <= 0 { break }
        data.append(buffer, count: n)
    }
    return data
}

func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        var offset = 0
        while offset < raw.count {
            let n = write(fd, base + offset, raw.count - offset)
            if n <= 0 { break }
            offset += n
        }
    }
}
