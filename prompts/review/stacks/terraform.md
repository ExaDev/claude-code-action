## Terraform

Detected from `.tf` files in the repository.

Infrastructure changes are the least reversible thing in this estate. A bad application deploy is rolled back; a destroyed database or a deleted state file is not. Review accordingly, and weight anything that could destroy or replace a stateful resource above everything else.

**Read the plan if you can reach it, and say so if you cannot.** The `.tf` diff shows intent; the plan shows consequence. If a plan output is available in the pull request or in a CI log you can read, work from it, and pay attention to every `destroy` and every `replace` (shown as `-/+` or "must be replaced"). Without a plan, say explicitly that your assessment is based on reading configuration only.

**Replacement is the trap.** Many arguments force a resource to be destroyed and recreated when changed, and for a database, a volume, a bucket, or anything holding state, that is data loss with a new identifier attached. Look at whether a changed argument is one that forces replacement, and whether the resource holds data. Also watch for changes that alter a resource's address rather than its configuration: renaming a resource block, or switching a resource between `count` and `for_each`, makes Terraform plan a destroy-and-create of every instance unless a `moved` block or a state move accompanies it. Migrating `count` to `for_each` reindexes everything, so `[0]` becomes `["name"]`.

**Guards on stateful resources.** Check that a database, bucket, or volume has `lifecycle { prevent_destroy = true }` where the project uses that pattern, that deletion protection and final-snapshot settings are on rather than off, and that a change does not quietly disable one. `skip_final_snapshot = true` on a production database is a finding.

**Secrets.** No credential, key, password, certificate, or connection string as a literal in a `.tf` file or a committed `.tfvars`. Remember that anything Terraform reads becomes plain text in the state file, so state must be treated as sensitive regardless. Outputs carrying a secret need `sensitive = true`. Flag any `.tfvars` or `.tfstate` added to the repository without being ignored.

**State and backend.** Check the backend is remote, versioned, and locking (an S3 backend with DynamoDB locking, or the equivalent), because local state means one person's laptop is the source of truth and concurrent applies corrupt it. Any change to backend configuration deserves close attention, since a mistake there orphans every resource.

**Versions.** `required_version` and every `required_providers` entry should be constrained, typically pessimistically (`~> 5.0`), and the lock file (`.terraform.lock.hcl`) should be committed and updated in the same change. An unconstrained provider means a future apply can pick up a major version and plan destruction nobody asked for.

**Exposure and access.** Check least privilege on anything new:

- Security-group and firewall rules opening `0.0.0.0/0` or `::/0`, especially on administrative ports. A database reachable from the internet is a finding even when it has a password.
- Storage made public: a bucket without its public-access block, or with a policy granting a wildcard principal.
- IAM policies with `Action: "*"`, `Resource: "*"`, or a wildcard principal. Ask what the workload actually needs.
- Encryption at rest and in transit left off where the provider makes it optional, and logging or audit trails disabled.

**Modules and structure.** A module source should be pinned to a tag or commit, not a branch. Check variables have types and descriptions, that a new variable has either a sensible default or a deliberate absence of one, and that `sensitive = true` is set where appropriate. Follow the repository's existing naming and tagging convention, since tags usually drive cost allocation and ownership. Watch for `local-exec` and `remote-exec` provisioners, which are an escape hatch that breaks the declarative model and often hides a manual step.

**Blast radius.** Say which environments a change affects and whether it is scoped to one workspace or applies everywhere. If a change touches shared networking, DNS, or an IAM role that other stacks assume, say so: the damage from those extends beyond the stack being changed.

If the project runs `tfsec`, `checkov`, or `terraform validate` in CI, do not duplicate their findings; concentrate on replacement risk, blast radius, and intent, which they cannot judge.
