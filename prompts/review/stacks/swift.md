## Swift

Detected from a Swift package or Xcode project alongside a SwiftLint configuration.

**Leave SwiftLint its job.** Formatting, line length, and naming rules are enforced already. Do not comment on those, and do not suggest a `// swiftlint:disable` to get past a rule.

**Optionals.** Flag `!` force-unwraps and `try!` and `as!` casts on anything not provably non-nil at that point; prefer `guard let`, `if let`, or `??`. Watch implicitly unwrapped optionals (`var x: Foo!`) on outlets and injected dependencies, where the crash arrives far from the mistake. An empty `catch {}` discards the error entirely.

**Memory.** The main source of leaks is a closure capturing `self` strongly where the object also owns the closure: escaping closures stored as properties, completion handlers, `Timer`, `NotificationCenter` observers, delegate properties declared `strong` rather than `weak`, and Combine `sink` bodies. Check for `[weak self]` with a `guard let self` at the top, and check the corresponding teardown exists: an observer added without being removed, a timer never invalidated, a cancellable never stored or cancelled.

**Concurrency.** This is where correctness usually breaks.

- UI work must be on the main actor. Look for a view model or view mutation from inside a `URLSession` completion handler or a background task without hopping back via `@MainActor` or `MainActor.run`.
- If the target has strict concurrency checking on, treat `Sendable` warnings as real: a non-`Sendable` reference type crossing an actor boundary is a data race the compiler is telling you about, not noise to be silenced with `@unchecked Sendable`. Flag any `@unchecked Sendable` that is not accompanied by an explanation of what actually protects the state.
- `Task { }` detached from any lifecycle keeps running after the view or view model goes away. Check whether it should be a `Task` stored and cancelled in `deinit`/`onDisappear`, and whether long loops check `Task.isCancelled`.
- Mixing completion handlers and `async`/`await` for the same operation invites double-calling or never-calling the continuation. A `withCheckedContinuation` resumed twice traps; resumed zero times it hangs forever. Check every path through the closure resumes exactly once.

**SwiftUI, if present.** Check state ownership matches the intent: `@State` for value-type state owned by the view, `@StateObject` for a reference-type object the view creates, `@ObservedObject` only for one passed in, `@EnvironmentObject` for one injected up the tree. Creating an `@ObservedObject` inline in a view body recreates it on every render and loses its state, which is a common and confusing bug. Watch for expensive work in a `body`, which runs far more often than people expect, and for missing stable `id` values in a `ForEach`.

**API and data.** `Codable` conformance should tolerate the payload the server actually sends: check optionality against reality rather than the happy path, and check `CodingKeys` cover renamed fields. Confirm `URLSession` requests have a timeout and that non-2xx responses are treated as failures rather than decoded blindly. Keychain and `UserDefaults` are not interchangeable: a token in `UserDefaults` is a finding.

**Package manifest.** Dependencies should be constrained (`.upToNextMajor(from:)` or exact), not pointed at a branch, which makes builds irreproducible. Check a new dependency is added to the right target and that its platform minimums do not quietly raise the package's own.
