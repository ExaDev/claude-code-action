## PHP

Detected from a `composer.json` file.

**Check what the project already enforces** before commenting on style: look for PHP-CS-Fixer or PHP_CodeSniffer configuration, and for PHPStan or Psalm with a declared level in `phpstan.neon` or `psalm.xml`. Do not repeat what those tools report, and never suggest a `@phpstan-ignore`, `@psalm-suppress`, or baseline entry to get past an error. Note whether the changed files carry `declare(strict_types=1)` where the rest of the project does.

**Injection is the first thing to look for**, because PHP makes it easy.

- Every SQL query built by string concatenation or interpolation with request data is a finding. Prepared statements with bound parameters, or the query builder the framework provides. Note that table and column names cannot be bound, so if one is dynamic it must be checked against an allowlist rather than escaped.
- Output must be escaped at the point of rendering: `htmlspecialchars` with an explicit encoding, or the templating engine's escaping. In Twig, flag `|raw`; in Blade, flag `{!! !!}`. Any of these applied to user-supplied data is an XSS hole.
- `shell_exec`, `exec`, `system`, `passthru`, and backticks with any request-derived component need `escapeshellarg`, and preferably an allowlist instead.
- `unserialize` on untrusted input allows object injection; use `json_decode`. `include`/`require` with a request-derived path is remote code execution. `eval` and `extract` on request data are both findings.
- Check file uploads validate the real type rather than the client-supplied extension or MIME header, and are stored outside the web root.

**Comparison and type juggling.** `==` performs coercion and is a recurring source of authentication bugs; prefer `===` and `!==`, especially when comparing a hash, token, or identifier. Compare secrets with `hash_equals`, not `===`, to avoid timing leaks. `in_array` and `array_search` need their third `strict` argument. `isset` and `empty` differ in ways that matter: `empty('0')` is true.

**Error handling.** The `@` suppression operator hides the failure and leaves you with a wrong value; remove it and handle the condition. A `catch (\Exception $e)` that logs and continues is a silent fallback, and it does not catch `\Error` anyway, so check whether `\Throwable` was intended. Confirm errors are not rendered to the response in production: a stack trace or query in an error page leaks structure.

**Types.** Prefer parameter, return, and property type declarations over docblock-only types. Where a docblock carries information the language cannot express, such as `@param list<array{id: int, name: string}>`, check it matches reality, since the static analyser trusts it. Flag a nullable return that callers dereference without checking.

**Framework conventions, if one is present.** Follow what the project already does rather than importing patterns from elsewhere.

- **Laravel:** mass assignment via `create`/`update` with unvalidated request data needs `$fillable` or explicit fields. Validate in a form request or explicitly, not ad hoc. Watch for N+1 queries from lazy relation access in a loop, and prefer eager loading with `with`. Business logic in a controller that belongs in a service or action, and raw `DB::raw` with interpolated input, are both worth flagging. Check queued jobs are idempotent.
- **Symfony:** services should be injected via the constructor rather than fetched from the container. Check voters or the security configuration actually cover a newly exposed route, and that Doctrine changes come with a migration.

**Composer.** Version constraints should be meaningful: `*` or `dev-master` make builds irreproducible. Confirm `composer.lock` is updated in the same change as `composer.json`, and that a package added as a runtime dependency is not really a development tool. Check autoload changes match the PSR-4 namespace mapping.
