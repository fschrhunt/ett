import Foundation

/// A user-facing failure. `main` prints the description prefixed with `ett:` and exits 1.
struct EttError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
