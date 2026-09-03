## Kotlin and Gradle

Detected from a Gradle build script alongside a ktlint or detekt configuration.

**Leave the linters their job.** ktlint owns formatting, import ordering, and layout; detekt owns much of the complexity and naming policing. Do not comment on anything either tool already reports, and never suggest adding `@Suppress` or `ktlintDisable` to get past a rule. If a rule is genuinely wrong for the code, say so and leave the decision to a human.

**Null safety.** The compiler covers most of this, so what remains is where it is being defeated. Flag `!!` on anything not immediately preceded by a check that guarantees it: prefer `?.`, `?:`, `requireNotNull` with a message, or a `let` block. Pay closer attention at Java or platform boundaries, where a `String!` platform type carries no guarantee and a value the compiler believes is non-null can still arrive null. `lateinit` is worth a look too: it converts a null into an `UninitializedPropertyAccessException` at some later point, so check the initialisation path really does run first.

**Coroutines.** This is where the real bugs are.

- Check every coroutine is launched in a scope with a defined lifetime. `GlobalScope` leaks work that outlives whatever started it and is almost always wrong; on Android, `viewModelScope` and `lifecycleScope` exist for this.
- `runBlocking` in production code blocks a thread and can deadlock. It belongs in tests and `main`, not in a request path or a UI callback.
- Confirm the dispatcher matches the work: `Dispatchers.IO` for blocking calls, `Dispatchers.Default` for CPU-bound work, the main dispatcher for UI. A blocking JDBC or file call on `Dispatchers.Main` or inside a `Default` worker starves the pool.
- Cancellation must be honoured. A `catch (e: Exception)` that swallows `CancellationException` breaks structured concurrency: rethrow it, or catch narrowly. Long loops without a suspension point never observe cancellation.
- `async` without a matching `await` silently discards both the result and the exception. In a `supervisorScope`, check failures are actually handled rather than merely isolated.
- Flow: check `collect` runs somewhere, that a cold flow is not being re-collected per item, and that `flowOn`, `buffer`, and `conflate` are where the author thinks they are.

**Types and modelling.** Prefer a sealed interface or sealed class over a string or integer discriminator, and prefer an exhaustive `when` with no `else` branch, so adding a case becomes a compile error rather than a silent fall-through. Watch for `when` on a non-sealed type where a new value would slip through. `data class` `equals` and `hashCode` cover the constructor properties only, which surprises people when a property is declared in the body.

**Collections and scope functions.** Look for chains that allocate an intermediate list per step where a `Sequence` or a single pass would do, particularly inside a loop. Nested `let`/`apply`/`also`/`run` blocks that shadow `it` are a readability trap and a genuine source of bugs when the wrong `it` is used.

**Exceptions and resources.** `use` for anything `Closeable`. A `catch (e: Exception)` that logs and continues is a silent fallback; ask whether the caller should have been told. Check that exceptions thrown across a coroutine or thread boundary are still surfaced.

**Gradle.** Dependencies belong in the version catalogue (`gradle/libs.versions.toml`) if the project has one, rather than as hardcoded coordinates. Watch for a dependency added as `implementation` when it appears in a public signature and so needs `api`, and for a version range or `latest.release`, which makes builds non-reproducible. Flag anything added to the root build script that belongs in a module.
