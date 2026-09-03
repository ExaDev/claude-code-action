## SvelteKit

Detected from a `package.json` declaring `@sveltejs/kit`.

**Leave the tooling its job.** `svelte-check`, ESLint, and Prettier are usually configured here; do not repeat their output. Do treat a `svelte-check` accessibility warning as a real finding rather than noise, because they catch genuine problems and are easy to dismiss.

**The server and client boundary is the highest-value thing to check**, because getting it wrong leaks secrets to the browser.

- `$env/static/private` and `$env/dynamic/private` must never be imported into anything that reaches the client. Kit will usually stop you, but check anything that changed under `$lib` and is imported from both sides.
- More subtly, whatever a `load` function returns is serialised into the page payload and is visible in the browser. A `+page.server.ts` load that returns a whole user or order record, when the page renders three fields of it, has published the rest. Check what is actually selected and returned.
- `+page.server.ts` and `+layout.server.ts` run only on the server; `+page.ts` and `+layout.ts` run in both places. Data fetched in a universal load with a secret, or with a direct database call, is a finding. Database access belongs in a `.server.` file.
- Check `+server.ts` endpoints and form actions authorise the request rather than assuming the UI would not have offered the action. An endpoint reachable by anyone who knows the URL is the actual security boundary, and broken access control here (loading a record by identifier without checking who is asking) is the most common real vulnerability in a Kit app.

**Forms and mutations.** Prefer form actions over hand-rolled `fetch` calls, since they degrade without JavaScript and Kit handles the wiring. Validate input on the server regardless of what the client checked. Return validation failures with `fail(400, { ... })` rather than throwing, and check nothing secret is put in that returned object, as it too reaches the browser. `redirect` and `error` must be thrown, not returned, and a `try`/`catch` around a `load` body can swallow them by accident, which turns a redirect into a silent success.

**Hooks.** `hooks.server.ts` `handle` is where authentication and `event.locals` population belong, so check a new protected route is actually covered by whatever pattern the project uses, rather than checking auth in each `load`. If `handleFetch` or `handleError` changed, check `handleError` does not return the raw error message to the client.

**Reactivity.** Determine whether the project is on Svelte 5 runes (`$state`, `$derived`, `$effect`) or the older store and `$:` style, and stay consistent with it rather than mixing.

- Under runes: `$derived` for anything computable from other state, not an `$effect` that assigns to `$state`, which is the usual cause of loops and stale values. Check `$effect` bodies for cleanup and for dependencies read conditionally, since only what was read is tracked. Reassignment is what triggers updates, so mutating a plain object or array in place may not.
- Under the older style: `$:` blocks re-run on dependency change, so check for accidental dependencies and for side effects that should be an event handler. A store subscribed without `$` prefix or without an unsubscribe leaks.

**Rendering and safety.** `{@html ...}` with anything user-supplied is an XSS hole and needs sanitising first. `{#each}` over anything that reorders needs a key. Watch for browser-only APIs (`window`, `document`, `localStorage`) at module top level or in a universal load, which breaks server rendering: they belong in `onMount` or behind a `browser` check.

**Configuration.** Check the adapter in `svelte.config.js` matches the deployment target, and that anything added to `vite.config` does not inline a secret via `define`. A new dependency that is server-only should not end up in the client bundle.
