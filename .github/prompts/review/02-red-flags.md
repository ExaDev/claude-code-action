## Red flags to watch for in diffs

- **Hallucinated APIs** — method calls or library functions that don't exist in the dependency version used
- **Phantom dependencies** — imports for packages not in `package.json` / `requirements.txt` / equivalent manifest
- **Silent failure** — try-catch returning fallbacks instead of propagating, optional chaining on data that should always exist, defaults on internal state hiding upstream bugs
- **Over-abstraction** — unnecessary design patterns or enterprise-grade abstractions for simple problems
- **Stale patterns** — deprecated APIs, outdated syntax, or patterns from older framework versions
- **Fixation / scope creep** — a fix for one issue applied shotgun-style across unrelated files, or unsolicited "improvements" to neighbouring code
- **Streisand artefacts** — comments about removed code (`// removed for security`), wrapper functions that exist only to hide a change, verbose disclaimers that draw more attention than the original issue
