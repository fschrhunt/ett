# ett

Emit typewriter text. A macOS command-line tool for demo recordings: save a
line, press its hotkey while the cursor is in any text field, and the line is
typed out at a natural pace. No more fumbling the take.

```
$ ett "npm install demo-tool"
saved slot 1, press ⌃⌥1

$ ett "Hello, this is the typed-out text"
saved slot 2, press ⌃⌥2

$ ett list
⌃⌥1  npm install demo-tool
⌃⌥2  Hello, this is the typed-out text

$ ett stop
stopped
```

Each slot is bound to the configured modifiers plus its digit, and stays
typable as many times as you need in any order. `ett 2 "new text"` replaces
slot 2. There are nine slots.

## How it works

The first `ett <text>` starts a small listener in the background that owns the
hotkeys and keeps the slots in memory. Later calls talk to it over a Unix
socket in your private temp directory. `ett stop` ends it, and everything is
gone. Nothing is written to disk except the settings file, and nothing starts
at login.

## Install

Needs Xcode command line tools.

```
swift build -c release
cp .build/release/ett ~/.local/bin/
```

Posting keystrokes requires Accessibility permission, which macOS attributes
to the terminal app that launched `ett`. If your terminal is not already
allowed under System Settings › Privacy & Security › Accessibility, keystrokes
are silently dropped and `ett` prints a note saying so. `ett` never opens that
dialog itself. Password fields reject synthetic keystrokes regardless.

## Settings

`~/.config/ett/config.json` is created with defaults on first run:

```json
{
  "modifier": "ctrl+opt",
  "minDelayMs": 40,
  "maxDelayMs": 110,
  "punctuationPauseMs": 120
}
```

- `modifier`: any of `cmd`, `opt`, `ctrl`, `shift` joined with `+`. Applied
  when the listener starts, so run `ett stop` after changing it.
- `minDelayMs`, `maxDelayMs`: each keystroke waits a random time in this
  range. Re-read on every press.
- `punctuationPauseMs`: extra pause after `. , ; : ! ?` and newlines.

`ctrl+opt` is the default because Command plus a digit switches browser tabs,
Option plus a digit types symbols, and Control plus a digit can switch Spaces.

## Development

Run `./x check` before proposing a change (`./x` defaults to it). It checks shell
syntax and compiles the release package in a temporary directory without launching
ett, registering hotkeys, or reading personal settings. macOS and Xcode command
line tools are required; other platforms fail explicitly rather than report a
partial check as passing. `./x help` lists the individual commands.
CI runs the same check on macOS for pull requests and pushes to main.

There is no automated runtime test suite yet. For hotkey/typing changes, report
manual verification and Accessibility limitations; a successful build does not
verify keystroke delivery. Update affected usage/settings documentation.
