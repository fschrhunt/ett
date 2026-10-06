import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Per-keystroke timing, taken from the config at the moment of the press.
struct Timing {
    var minDelayMs: Int
    var maxDelayMs: Int
    var punctuationPauseMs: Int

    init(_ config: Config) {
        minDelayMs = config.minDelayMs
        maxDelayMs = config.maxDelayMs
        punctuationPauseMs = config.punctuationPauseMs
    }
}

/// Types text into the focused field one character at a time with human-ish timing.
/// Runs on its own serial queue so the listener keeps answering while typing; presses
/// that arrive mid-typing are dropped rather than queued.
final class Typer {
    private let queue = DispatchQueue(label: "ett.typer")
    private let lock = NSLock()
    private var busy = false
    private static let pauseAfter: Set<Character> = [".", ",", ";", ":", "!", "?", "\n"]

    func type(_ text: String, timing: Timing) {
        lock.lock()
        let wasBusy = busy
        busy = true
        lock.unlock()
        if wasBusy { return }
        queue.async {
            self.run(text, timing: timing)
            self.lock.lock()
            self.busy = false
            self.lock.unlock()
        }
    }

    private func run(_ text: String, timing: Timing) {
        let source = CGEventSource(stateID: .hidSystemState)
        waitForModifierRelease()
        for character in text {
            post(character, source: source)
            var delay = Int.random(in: timing.minDelayMs...timing.maxDelayMs)
            if Self.pauseAfter.contains(character) { delay += timing.punctuationPauseMs }
            usleep(useconds_t(delay) * 1000)
        }
    }

    /// The hotkey's modifiers are usually still held when typing starts. Posting
    /// characters while they're down would turn them into shortcuts, so wait briefly.
    private func waitForModifierRelease() {
        let deadline = Date().addingTimeInterval(2)
        let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        while Date() < deadline {
            if CGEventSource.flagsState(.hidSystemState).intersection(held).isEmpty { return }
            usleep(10_000)
        }
    }

    private func post(_ character: Character, source: CGEventSource?) {
        switch character {
        case "\n", "\r\n", "\r": postKey(CGKeyCode(kVK_Return), source: source)
        case "\t": postKey(CGKeyCode(kVK_Tab), source: source)
        default:
            var units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                event.flags = []
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func postKey(_ keyCode: CGKeyCode, source: CGEventSource?) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }
}
