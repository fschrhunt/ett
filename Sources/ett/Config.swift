import Carbon.HIToolbox
import Foundation

/// User settings from ~/.config/ett/config.json.
///
/// The file is created with defaults the first time the listener starts. Keys that
/// are missing from the file fall back to their defaults. Timing keys are re-read on
/// every hotkey press; `modifier` is applied when the listener starts.
struct Config: Codable {
    var modifier = "ctrl+opt"
    var minDelayMs = 40
    var maxDelayMs = 110
    var punctuationPauseMs = 120

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ett", isDirectory: true)
    static let path = directory.appendingPathComponent("config.json")

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modifier = try c.decodeIfPresent(String.self, forKey: .modifier) ?? modifier
        minDelayMs = try c.decodeIfPresent(Int.self, forKey: .minDelayMs) ?? minDelayMs
        maxDelayMs = try c.decodeIfPresent(Int.self, forKey: .maxDelayMs) ?? maxDelayMs
        punctuationPauseMs = try c.decodeIfPresent(Int.self, forKey: .punctuationPauseMs) ?? punctuationPauseMs
    }

    /// Loads the config, writing a default file if none exists, and validates it.
    static func load() throws -> Config {
        let config: Config
        if let data = try? Data(contentsOf: path) {
            do {
                config = try JSONDecoder().decode(Config.self, from: data)
            } catch {
                throw EttError("could not parse \(path.path): \(error.localizedDescription)")
            }
        } else {
            config = Config()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: path)
        }
        guard config.minDelayMs >= 0, config.maxDelayMs >= config.minDelayMs, config.punctuationPauseMs >= 0 else {
            throw EttError("invalid delays in \(path.path): need 0 <= minDelayMs <= maxDelayMs and punctuationPauseMs >= 0")
        }
        _ = try Modifiers(config.modifier)
        return config
    }
}

/// A modifier combination such as "ctrl+opt", parsed into Carbon flags and Mac symbols.
struct Modifiers {
    let carbon: UInt32
    /// Apple's display order: ⌃ ⌥ ⇧ ⌘.
    let symbols: String

    init(_ spec: String) throws {
        var flags: UInt32 = 0
        for token in spec.lowercased().split(separator: "+") {
            switch token.trimmingCharacters(in: .whitespaces) {
            case "cmd", "command", "⌘": flags |= UInt32(cmdKey)
            case "opt", "option", "alt", "⌥": flags |= UInt32(optionKey)
            case "ctrl", "control", "⌃": flags |= UInt32(controlKey)
            case "shift", "⇧": flags |= UInt32(shiftKey)
            case let other: throw EttError("unknown modifier \"\(other)\" in \"\(spec)\"; use cmd, opt, ctrl, shift joined with +")
            }
        }
        guard flags != 0 else { throw EttError("modifier must name at least one of cmd, opt, ctrl, shift") }
        carbon = flags
        var s = ""
        if flags & UInt32(controlKey) != 0 { s += "⌃" }
        if flags & UInt32(optionKey) != 0 { s += "⌥" }
        if flags & UInt32(shiftKey) != 0 { s += "⇧" }
        if flags & UInt32(cmdKey) != 0 { s += "⌘" }
        symbols = s
    }
}
