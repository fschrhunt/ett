import Foundation

/// The CLI side: talks to the listener over its socket, starting it on demand.
enum Client {
    /// Sends a request and returns the response, or nil when the listener is not
    /// running and `autostart` is false.
    static func send(_ request: Request, autostart: Bool) throws -> Response? {
        let path = socketPath()
        let addr = try unixAddress(path)
        var fd = connect(addr)
        if fd < 0 {
            guard autostart else { return nil }
            unlink(path)  // leftover from a listener that died
            let pid = try spawnListener()
            fd = try waitForListener(addr, pid: pid)
        }
        defer { close(fd) }
        writeAll(fd, try JSONEncoder().encode(request))
        shutdown(fd, SHUT_WR)
        let data = readToEOF(fd)
        guard !data.isEmpty else { throw EttError("listener closed the connection without replying") }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func connect(_ addr: sockaddr_un) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        if withSockaddr(addr, { Darwin.connect(fd, $0, $1) }) == 0 { return fd }
        close(fd)
        return -1
    }

    /// Starts `ett --daemon` as a detached process in its own session, so it outlives
    /// this shell and never receives its SIGHUP. stdin and stdout go to /dev/null.
    /// stderr is a pipe back to us: the listener writes startup errors there and then
    /// drops it once it is serving, so we see failures without holding its output open.
    private static func spawnListener() throws -> pid_t {
        guard let exe = Bundle.main.executablePath else { throw EttError("cannot locate own executable") }
        var pipeFds: [Int32] = [-1, -1]
        guard pipe(&pipeFds) == 0 else { throw EttError("pipe: \(String(cString: strerror(errno)))") }
        let (readEnd, writeEnd) = (pipeFds[0], pipeFds[1])

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeEnd, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, readEnd)
        posix_spawn_file_actions_addclose(&actions, writeEnd)

        let args: [UnsafeMutablePointer<CChar>?] = [strdup(exe), strdup("--daemon"), nil]
        defer { args.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exe, &actions, &attr, args, environ)
        close(writeEnd)
        guard rc == 0 else {
            close(readEnd)
            throw EttError("could not start listener: \(String(cString: strerror(rc)))")
        }

        // Blocks until the listener is serving (it closes its end) or has exited.
        let startupOutput = readToEOF(readEnd)
        close(readEnd)
        if !startupOutput.isEmpty {
            let message = String(decoding: startupOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = message.hasPrefix("ett: ") ? String(message.dropFirst(5)) : message
            throw EttError(stripped)
        }
        return pid
    }

    /// Polls until the listener accepts connections, or reports that it exited.
    private static func waitForListener(_ addr: sockaddr_un, pid: pid_t) throws -> Int32 {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let fd = connect(addr)
            if fd >= 0 { return fd }
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid {
                throw EttError("listener failed to start")
            }
            usleep(30_000)
        }
        throw EttError("listener did not start in time")
    }
}
