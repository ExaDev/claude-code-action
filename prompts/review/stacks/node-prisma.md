## Node with Prisma

Detected from a `package.json` alongside a Prisma schema or dependency. Where the project also uses Fastify, the route conventions below apply.

### Prisma schema and migrations

Treat migrations as the highest-severity part of any change here, because they are the one thing that cannot be rolled back by reverting a commit.

- **Destructive changes.** A dropped column or table, a renamed field (which Prisma implements as drop-then-add unless the migration is hand-edited, silently discarding the data), a narrowed type, or a tightened length. Each needs a deliberate answer, and a rename almost always needs the generated SQL edited by hand.
- **Adding a required column.** `NOT NULL` without a default fails outright on a non-empty table. The safe sequence is: add it nullable, backfill, then tighten in a later migration. Flag any single migration that tries to do it in one step.
- **A new unique constraint or index** on existing data fails if the data violates it, and building an index locks the table on some engines. Ask whether the data has been checked and whether the table is large.
- **Check the generated SQL, not just the schema diff.** `prisma/migrations/**` is the artefact that runs against production; the `schema.prisma` diff only says what was intended.
- Migrations already applied must never be edited: a changed checksum makes `migrate deploy` fail. A migration edited in place is a finding unless it has demonstrably never been applied anywhere.
- Check the deployment path uses `prisma migrate deploy`. `migrate dev` is a development command that can reset the database, and `db push` skips migration history entirely, so neither belongs in CI or a release script.
- Confirm `schema.prisma` changes come with a migration at all: a schema edited without one leaves the client and the database disagreeing at runtime.

### Prisma query usage

- **N+1 queries.** A `findMany` followed by a per-row `findUnique` in a loop, or a relation accessed inside a `map`, should be one query with `include` or `select`. This is the most common performance defect in Prisma code.
- **Prefer `select` to `include`** for anything crossing a trust or network boundary, so new columns added later do not silently start being returned. Watch for a query that returns a whole user record, password hash and all, into an API response.
- **Multi-step writes need `$transaction`.** Two dependent `update` calls without one leave the database inconsistent when the second fails. Check that an interactive transaction does not perform an HTTP call inside it, which holds a connection open.
- `$queryRawUnsafe` and `$executeRawUnsafe` with interpolated input are SQL injection. `$queryRaw` with a tagged template parameterises properly; check the change did not switch from one to the other.
- Check that `PrismaClient` is instantiated once per process, not per request or per module import, which exhausts the connection pool. In a serverless or edge deployment, confirm the project's pooling arrangement is respected and connection limits are set deliberately.
- `findUniqueOrThrow` and `findFirstOrThrow` throw on absence, so check the caller expects that; conversely, check a `findUnique` result is null-checked before use.
- `upsert` races under concurrency and can still throw a unique-constraint error; check that is handled where it matters.

### Fastify routes

- **Validate at the boundary with a schema.** Every route should declare `body`, `querystring`, and `params` schemas, so unvalidated input cannot reach a handler, and a `response` schema, which also serialises faster. A handler that reads `request.body` fields with no schema is a finding. If the project uses Zod or TypeBox with a type provider, follow that pattern rather than introducing a second one.
- A `response` schema strips undeclared properties, which is a security feature: check a route returning a database record has one, or is explicitly selecting fields.
- **Async handlers must return, not call `reply.send`, and never both.** Returning a value after `reply.send` sends twice. An `async` handler with a callback-style `done` never resolves.
- Errors: an `async` handler's thrown error is handled by Fastify, so check nothing swallows it into a 200 response. Confirm `setErrorHandler` does not leak internal messages or stack traces to the client.
- **Plugin encapsulation.** Anything registered inside a plugin is scoped to it, so a hook or decorator meant to be global must be registered at the root or wrapped with `fastify-plugin`. A decorator added inside a plugin and used elsewhere is a runtime failure.
- Check authentication is enforced by a hook covering the route group rather than repeated per handler, and that a newly added route is inside the protected scope.
- Register rate limiting, CORS, and helmet-equivalent headers at the appropriate scope; check a new public route is not exempted by accident.

### General

Check `tsconfig.json` strictness is respected rather than worked around: a new `any`, a `as` assertion, or a `@ts-ignore` in the diff is a finding, and `!` non-null assertions on Prisma results are usually hiding a real nullable. Confirm secrets come from validated environment configuration rather than `process.env` read inline with a `??` fallback, and that a new dependency is in `dependencies` rather than `devDependencies` if it runs in production.
