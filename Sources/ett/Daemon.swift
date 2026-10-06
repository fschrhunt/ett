import ApplicationServices
import Foundation

/// The listener: holds the slots in memory, owns the hotkeys, and answers the CLI
/// over the socket. Everything lives in this process; `stop` ends it and nothing
/// is left behind except the config file.
final class Daemon {
    private var slots: [Int: String] = [:]
    private let modifiers: Modifiers
    private let typer = Typer()
    private let path = socketPath()
    private var listenFd: Int32 = -1
    private var sources: [DispatchSourceProtocol] = []

    init(config: Config) throws {
        modifiers = try Modifiers(config.modifier)
    }

    func run() throws -> Never {
        try Hotkeys.register(modifiers: modifiers) { [unowned self] slot in self.press(slot) }
        try bind()
        installSignalHandlers()
        releaseStderr()
        CFRunLoopRun()
        exit(0)
    }

    // MARK: Hotkeys

    private func press(_ slot: Int) {
        guard let text = slots[slot] else { return }
        // Re-read so timing edits apply without a restart; keep going on a bad file.
        let config = (try? Config.load()) ?? Config()
        typer.type(text, timing: Timing(config))
    }

    // MARK: Socket

    private func bind() throws {
        let addr = try unixAddress(path)
        // Refuse to start twice. A stale socket file from a dead listener is replaced.
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        if withSockaddr(addr, { connect(probe, $0, $1) }) == 0 {
            close(probe)
            throw EttError("listener already running")
        }
        close(probe)
        unlink(path)

        listenFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFd >= 0 else { throw EttError("socket: \(String(cString: strerror(errno)))") }
        guard withSockaddr(addr, { Darwin.bind(listenFd, $0, $1) }) == 0 else {
            throw EttError("bind \(path): \(String(cString: strerror(errno)))")
        }
        guard listen(listenFd, 8) == 0 else { throw EttError("listen: \(String(cString: strerror(errno)))") }

        let source = DispatchSource.makeReadSource(fileDescriptor: listenFd, queue: .main)
        source.setEventHandler { [unowned self] in self.acceptOne() }
        source.resume()
        sources.append(source)
    }

    private func acceptOne() {
        let fd = accept(listenFd, nil, nil)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let response: Response
        var stopAfterReply = false
        do {
            let request = try JSONDecoder().decode(Request.self, from: readToEOF(fd))
            response = handle(request)
            stopAfterReply = request.command == .stop
        } catch {
            response = Response(ok: false, error: "bad request: \(error.localizedDescription)")
        }
        writeAll(fd, (try? JSONEncoder().encode(response)) ?? Data())
        if stopAfterReply { shutdownAndExit() }
    }

    private func handle(_ request: Request) -> Response {
        let trusted = AXIsProcessTrusted()
        switch request.command {
        case .set:
            guard let text = request.text, !text.isEmpty else { return Response(ok: false, error: "nothing to save") }
            let slot: Int
            if let wanted = request.slot {
                guard (1...slotCount).contains(wanted) else { return Response(ok: false, error: "slot must be 1 to \(slotCount)") }
                slot = wanted
            } else if let free = (1...slotCount).first(where: { slots[$0] == nil }) {
                slot = free
            } else {
                return Response(ok: false, error: "all \(slotCount) slots are full; replace one with `ett <n> <text>` or run `ett stop`")
            }
            slots[slot] = text
            return Response(ok: true, slot: slot, hotkey: hotkey(slot), trusted: trusted)
        case .list:
            let entries = slots.keys.sorted().map { SlotEntry(slot: $0, hotkey: hotkey($0), text: slots[$0]!) }
            return Response(ok: true, slots: entries, trusted: trusted)
        case .stop:
            return Response(ok: true)
        }
    }

    private func hotkey(_ slot: Int) -> String { modifiers.symbols + String(slot) }

    /// Startup is over: let go of the stderr the CLI lent us (see Client.spawnListener)
    /// so nothing we hold keeps the shell, or an SSH session, waiting on us.
    private func releaseStderr() {
        let devnull = open("/dev/null", O_WRONLY)
        if devnull >= 0 {
            dup2(devnull, STDERR_FILENO)
            close(devnull)
        }
    }

    // MARK: Shutdown

    private func installSignalHandlers() {
        signal(SIGPIPE, SIG_IGN)
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [unowned self] in self.shutdownAndExit() }
            source.resume()
            sources.append(source)
        }
    }

    private func shutdownAndExit() -> Never {
        if listenFd >= 0 { close(listenFd) }
        unlink(path)
        exit(0)
    }
}
