import Foundation

/// ett: emit typewriter text. Saves a line to a numbered slot and types it out
/// wherever the cursor is when the slot's hotkey is pressed.
///
///   ett <text>        save to the lowest free slot
///   ett <n> <text>    save to slot n (1...9), replacing what was there
///   ett list          show what's loaded
///   ett stop          stop the listener; everything is forgotten
///   ett --daemon      internal: run the listener in the foreground

let usage = """
usage:
  ett <text>        save text to the lowest free slot and print its hotkey
  ett <n> <text>    save text to slot n (1-9), replacing it
  ett list          show saved slots
  ett stop          stop the listener and forget all slots

Nothing is stored on disk except settings in \(Config.path.path)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ett: \(message)\n".utf8))
    exit(1)
}

func check(_ response: Response) -> Response {
    guard response.ok else { fail(response.error ?? "unknown error") }
    return response
}

/// One line per slot, with newlines flattened so the table stays aligned.
func oneLine(_ text: String) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: "⏎")
    return flat.count > 70 ? String(flat.prefix(69)) + "…" : flat
}

func accessibilityNote(_ response: Response) {
    if response.trusted == false {
        print("note: keystrokes are dropped until your terminal app is allowed under Privacy & Security › Accessibility")
    }
}

let args = Array(CommandLine.arguments.dropFirst())

do {
    switch args {
    case [], ["help"], ["-h"], ["--help"]:
        print(usage)

    case ["--daemon"]:
        try Daemon(config: Config.load()).run()

    case ["list"]:
        guard let response = try Client.send(Request(command: .list), autostart: false) else {
            print("not running")
            exit(0)
        }
        let entries = check(response).slots ?? []
        if entries.isEmpty { print("no slots saved") }
        for entry in entries { print("\(entry.hotkey)  \(oneLine(entry.text))") }
        accessibilityNote(response)

    case ["stop"]:
        guard let response = try Client.send(Request(command: .stop), autostart: false) else {
            print("not running")
            exit(0)
        }
        _ = check(response)
        print("stopped")

    default:
        var slot: Int?
        var words = args
        // Two words with a leading integer means "slot n, text"; the listener range-checks n.
        if words.count == 2, let n = Int(words[0]) {
            slot = n
            words.removeFirst()
        }
        let text = words.joined(separator: " ")
        let request = Request(command: .set, slot: slot, text: text)
        guard let response = try Client.send(request, autostart: true) else { fail("listener not running") }
        let saved = check(response)
        print("saved slot \(saved.slot!), press \(saved.hotkey!)")
        accessibilityNote(saved)
    }
} catch let error as EttError {
    fail(error.description)
} catch {
    fail(error.localizedDescription)
}
