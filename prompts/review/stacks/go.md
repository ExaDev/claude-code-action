## Go

Detected from a `go.mod` file.

**Leave the tooling its job.** `gofmt` settles formatting and `golangci-lint` (check `.golangci.yml` for which linters are on) covers a great deal of what is worth saying mechanically. Do not comment on formatting, and never suggest a `//nolint` directive to get past a rule.

**Errors.** This is where most Go review value lies.

- An ignored error is a finding. `_ = doThing()` and a bare call to a function returning `error` both discard information. `defer f.Close()` on a writable file discards a flush error that means data loss; assign it in a named return or handle it explicitly.
- Wrapping must preserve the chain: `fmt.Errorf("reading config: %w", err)`, not `%v` or `%s`, which breaks `errors.Is` and `errors.As` downstream. Compare with `errors.Is` rather than `==`, and never by matching on `err.Error()` text.
- Error messages should not be capitalised or end in punctuation, and should add context rather than restate the callee.
- A library must not `panic` for an ordinary failure; return an error. `log.Fatal` inside anything other than `main` takes the process down and skips every deferred call.
- Check for the sentinel-vs-typed-error mismatch: returning a wrapped error but comparing it with `==` somewhere else in the diff.

**Context.** A function doing I/O should take `context.Context` as its first parameter and pass it down rather than reaching for `context.Background()` or `context.TODO()` mid-call-chain. Check the context is actually honoured: passed to the database call, the HTTP request, the loop's select. Every `context.WithCancel` and `context.WithTimeout` returns a `cancel` that must be deferred, or the timer leaks.

**Goroutines and races.**

- Every `go func()` needs an answer to "who waits for this, and how does it stop?" A goroutine writing to an unbuffered channel nobody reads leaks for the life of the process. Check for `sync.WaitGroup` with `Add` outside the goroutine and `Done` deferred inside, or a context the goroutine selects on.
- Shared mutable state needs a mutex or a channel. A read of a map while another goroutine writes it is a race that crashes the process. Watch for a mutex copied by value, or a `sync.Mutex` held across a network call.
- Writing to a `nil` map panics; declaring `var m map[string]T` without `make` is a common cause.
- `defer` inside a loop runs at function exit, not iteration exit, so file handles and locks accumulate. Extract the loop body into a function.

**Slices and aliasing.** `append` may or may not reallocate, so a slice retained after `append` may or may not observe later writes: this bites when a subslice is stored or returned. `s[:n]` shares the backing array with `s`, so mutating one mutates the other. Copy explicitly where ownership transfers. Also watch the classic subtle one: taking the address of a loop variable, or capturing it in a goroutine, when the code targets a Go version before the per-iteration loop-variable semantics.

**HTTP and external calls.** `http.DefaultClient` has no timeout, so a hung server hangs your process; check for an explicit `http.Client{Timeout: ...}` or per-request context deadline. Every response body must be closed, and closed even on a non-2xx status, or connections leak. Check the status code is inspected before the body is decoded.

**Interfaces and API shape.** Accept interfaces, return concrete types. A single-implementation interface defined next to its only implementation is usually premature. Exported identifiers are a compatibility commitment: flag a change to an exported signature, struct field, or constant and ask who depends on it.

**Tests.** Prefer table-driven tests with named cases. Check subtests calling `t.Parallel()` do not share mutable state, and that the test asserts on behaviour rather than on the mock it just configured.
