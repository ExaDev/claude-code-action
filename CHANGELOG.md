## [1.1.0](https://github.com/ExaDev/claude-code-action/compare/v1.0.0...v1.1.0) (2026-09-03)

### Bug Fixes

- **lint:** exclude the generated CHANGELOG.md from markdown lint ([a86559a](https://github.com/ExaDev/claude-code-action/commit/a86559a5a5c5f0fbb993e0fbd2e600c53864a4aa))
- **prompts:** exclude gh api from what counts as an issue-creation tool ([e69ad48](https://github.com/ExaDev/claude-code-action/commit/e69ad48b6c1ce2676768f224fdb6849ec1a0c186))
- **prompts:** make the out-of-scope issue-filing instruction mode-aware ([4512030](https://github.com/ExaDev/claude-code-action/commit/451203073a1185b0062f850074351e55c95d40c4))

### Features

- **prompts:** add a closing-keyword pass to the title/description fix ([b36b935](https://github.com/ExaDev/claude-code-action/commit/b36b935d72c0e505434b5ee60787999e8f98b0ab))
- **prompts:** add a Conduct section to interactive mode ([794ae49](https://github.com/ExaDev/claude-code-action/commit/794ae4943e8bdd9db51c7dc01894ae6028422a08))
- **prompts:** restore hallucinated-API and Streisand-artefact review checks ([fd67916](https://github.com/ExaDev/claude-code-action/commit/fd679164481777a9be337ec0423df945e76e4cb0))

## 1.0.0 (2026-09-03)

### Bug Fixes

- **action:** allow gh api graphql commands in review mode ([a8f17c5](https://github.com/ExaDev/claude-code-action/commit/a8f17c5a658ca6f8824a63cbd9e8293ca5df303b))
- **action:** use Claude App token by default for claude[bot] identity ([db0bfe7](https://github.com/ExaDev/claude-code-action/commit/db0bfe72fdbec9ecec5a742d4c31a0a7dffa3729))
- add the missing format-changelog semantic-release plugin ([84bf62a](https://github.com/ExaDev/claude-code-action/commit/84bf62ae3a5bd05ea1ee0ee42294f8b033d1955f))
- address review feedback on upstream-sync workflow ([7c6a035](https://github.com/ExaDev/claude-code-action/commit/7c6a035803bf3fcb5aff8fae39c17fa257aac512))
- allow claude[bot] PRs to be reviewed ([18c9049](https://github.com/ExaDev/claude-code-action/commit/18c9049b4173825e3626e896d8a6a00b32df6c02))
- always create PR instead of pushing directly to main ([6cde541](https://github.com/ExaDev/claude-code-action/commit/6cde54179aa4359c40c8bee2607a4c977baa5042))
- clone target repo directly instead of using git remote ([f150bdc](https://github.com/ExaDev/claude-code-action/commit/f150bdc2598bebd39081b296b58489ca8aeb35ba))
- correct pr_number override gaps and triage prompt placeholder syntax ([af53260](https://github.com/ExaDev/claude-code-action/commit/af53260e325728cb2290a4b146c20f15858107eb))
- correct this repository's own dogfooding interactive trigger ([7c264c0](https://github.com/ExaDev/claude-code-action/commit/7c264c02283d36110cec2ebd34085e0999ac4496))
- **prompts:** add concrete gh pr edit example for description updates ([6a979ef](https://github.com/ExaDev/claude-code-action/commit/6a979ef6288411b80fa71c57638777997c92a6fa))
- **prompts:** avoid redundant PR description updates ([f4f05ac](https://github.com/ExaDev/claude-code-action/commit/f4f05acd25df235fe5dc6f14c7d9b6ccf895da93))
- **prompts:** clarify PR description update instruction ([ea53c9e](https://github.com/ExaDev/claude-code-action/commit/ea53c9ecd3af1df6c8f5b6830bcf8036b6cc2c57))
- **prompts:** instruct bot to comment on PR when errors block execution ([ae02f0f](https://github.com/ExaDev/claude-code-action/commit/ae02f0f2a90f9b821c0e4037901ab27e7b603afd))
- **prompts:** remove label management and add PR title checking ([0969afc](https://github.com/ExaDev/claude-code-action/commit/0969afc1ff30aad7d22448754772009f92d71e20))
- **prompts:** require API verification before flagging hallucinated APIs ([0278704](https://github.com/ExaDev/claude-code-action/commit/0278704f41bae57e84a3d8485ee2301304ebaf55))
- **prompts:** require re-verification of prior technical claims during cleanup ([7d6a60a](https://github.com/ExaDev/claude-code-action/commit/7d6a60ab0d6bdbc416537d829360395fbddabb9b))
- **prompts:** use dynamic bot identity for comment filtering ([e1e7802](https://github.com/ExaDev/claude-code-action/commit/e1e780293196b31f504426ebcced25af0bf3deec))
- **prompts:** use static BOT_NAME instead of GraphQL identity query ([7b3eb30](https://github.com/ExaDev/claude-code-action/commit/7b3eb30ee885fa88118c1f0b45bb97388895dff0))
- push directly to URL instead of using git remote ([9b8a38c](https://github.com/ExaDev/claude-code-action/commit/9b8a38cd79eb6cb6787587de77bc7b044eefcd5a))
- remove duplicate display_report input and pass-through ([09567a4](https://github.com/ExaDev/claude-code-action/commit/09567a41b5e129af728646769de0f1778c6b19e1))
- remove unnecessary Bash(date:*) from allowedTools ([208c0e4](https://github.com/ExaDev/claude-code-action/commit/208c0e450952300a81aea8d87c88e5bec4ad4bbe))
- resolve empty mapping value lint error in upstream-sync workflow ([c188114](https://github.com/ExaDev/claude-code-action/commit/c188114a828c99549a8d98477b3ecf0a103f69a8))
- restore mode's implicit default and claude_args as a full override ([309a4ae](https://github.com/ExaDev/claude-code-action/commit/309a4aec7e3522b635d87e62203470fc2a296157))
- run the Dependabot review job from a trusted base-ref checkout ([657fe90](https://github.com/ExaDev/claude-code-action/commit/657fe9008672b066e79747f7cba97006c7ec23c3))
- simplify token handling to use adpeak token directly ([5f36efe](https://github.com/ExaDev/claude-code-action/commit/5f36efeb51a604538b29f6da4d8504528050e0e4))
- **sync:** add workflows write permission ([309e4c2](https://github.com/ExaDev/claude-code-action/commit/309e4c29c6df4e94329e15b416c443d3d818a59d))
- **sync:** correct remote reference in PR creation step ([658a0ae](https://github.com/ExaDev/claude-code-action/commit/658a0ae64e3feefd09977fefd0470f02343252d6))
- **sync:** improve workflow security and prevent loops ([00db966](https://github.com/ExaDev/claude-code-action/commit/00db966e86e76bb28e3460d593515d9717ccc9e6))
- **sync:** push source/main directly to handle divergence ([aa83a73](https://github.com/ExaDev/claude-code-action/commit/aa83a7332a225863471c59b6126c0f794951048f))
- **sync:** simplify PR creation using gh API ([a852eb4](https://github.com/ExaDev/claude-code-action/commit/a852eb487b02ad257c3b174368e27d91cb331b14))
- **sync:** use conditional token generation to avoid multi-line output issue ([6f96571](https://github.com/ExaDev/claude-code-action/commit/6f96571fb8a1c9487b999ad860559cd73c58e65f))
- **sync:** use dynamic token selection for bidirectional support ([1720dfe](https://github.com/ExaDev/claude-code-action/commit/1720dfe58ad0485e18ef6fbd17ac1f8740be46c9))
- **sync:** use gh api for PR creation to enable auto-merge ([fbab103](https://github.com/ExaDev/claude-code-action/commit/fbab10355b0ef5bd9e0c7b6f3c23c4c2bdd6197f))
- **sync:** use GITHUB_TOKEN for source repo access ([f8aaf24](https://github.com/ExaDev/claude-code-action/commit/f8aaf24cc6842c5a46e77ef6e9e129a25f1cd2e6))
- **sync:** use organization mode for GitHub App token retrieval ([65186e6](https://github.com/ExaDev/claude-code-action/commit/65186e6d325a4e314b7f5ae9899a5e2f6016130a))
- **sync:** use remote fetch instead of worktree for cross-repo sync ([bd0a7c5](https://github.com/ExaDev/claude-code-action/commit/bd0a7c5ac0e607e6cfff34cb1d03f19fa370e863))
- **sync:** use target org's GitHub App credentials for bidirectional sync ([91888d0](https://github.com/ExaDev/claude-code-action/commit/91888d0c0fa845ba40765113165524b4092b50fa))
- **triage:** wire up triage_label and update_issue_body variables ([e09400a](https://github.com/ExaDev/claude-code-action/commit/e09400a4a79360ea2fdcd30f55b7b15ddb2162de))
- **upstream-sync:** allow shell utilities in Claude Code allowed tools ([e2609c8](https://github.com/ExaDev/claude-code-action/commit/e2609c81ecbb4a51fb27bf584d8030ceb44e4412))
- **upstream-sync:** improve upstream reference section in PR template ([15756fe](https://github.com/ExaDev/claude-code-action/commit/15756fe068cc77c99d054869edd1e914af99a87d))
- **upstream-sync:** specify release.json field names in prompt ([ed46f8d](https://github.com/ExaDev/claude-code-action/commit/ed46f8d0bb5f670454fc5a20d8d83a61a92fb417))
- use GraphQL viewer query instead of REST API ([09a5d59](https://github.com/ExaDev/claude-code-action/commit/09a5d599d2c7491314a0db657784ecadcaef9726))
- use unique directory name for target repo clone ([dd2a4eb](https://github.com/ExaDev/claude-code-action/commit/dd2a4ebd87edd3bb3be4b582137dc949e28b0c13))
- **workflow:** grant permissions for reusable workflow ([8e46213](https://github.com/ExaDev/claude-code-action/commit/8e46213021cfb51feb28fb0dc4b3978990c79107))
- **workflow:** handle empty directories and error responses in download script ([3d8affc](https://github.com/ExaDev/claude-code-action/commit/3d8affcaeca882e0e97fd69a355e5f4a40144646))
- **workflow:** pass APP_ID and APP_PRIVATE_KEY secrets to reusable workflow ([006713f](https://github.com/ExaDev/claude-code-action/commit/006713f9ac26a480d170353d12a02204d57914e7))
- **workflows:** convert space-separated tools to comma-separated ([da5b290](https://github.com/ExaDev/claude-code-action/commit/da5b290e39dff4cfc67910b124c3dcab3c4fc319))
- **workflow:** scope App token to claude-code-action repo ([90bdc7f](https://github.com/ExaDev/claude-code-action/commit/90bdc7f393f3b1700e5673b12f06039a717aec5f))
- **workflows:** correct mode check from code-review to review ([f9c4524](https://github.com/ExaDev/claude-code-action/commit/f9c4524f2b620c862885d1be780f8810ef83ade9))
- **workflow:** try ACTIONS_RUNTIME_TOKEN for cross-repo API access ([45250c6](https://github.com/ExaDev/claude-code-action/commit/45250c66ff6fa2eba6afb6829a223f65d5c3f759))
- **workflow:** use GitHub API instead of checkout for shared prompts ([24a9bff](https://github.com/ExaDev/claude-code-action/commit/24a9bff39177036220cf23f3c3b0580423980700))
- **workflow:** use secrets: inherit for reusable workflow ([9fa6914](https://github.com/ExaDev/claude-code-action/commit/9fa691493df9027b10e0bbded1be15187a68b124))

### chore

- remove sync tooling superseded by direct consolidation ([17025ea](https://github.com/ExaDev/claude-code-action/commit/17025ea6a4a728d89a90dccf2eb476bdf61c372e))

### Features

- **action:** add upstream v1.0 pass-through inputs ([a9971cb](https://github.com/ExaDev/claude-code-action/commit/a9971cb44441659b1d4a8a073c5fcb3d43eb76a3))
- **action:** pass BOT_NAME to prompt templates via envsubst ([7e4acf4](https://github.com/ExaDev/claude-code-action/commit/7e4acf41f4638df919913a8fa35c55f0619a48a2))
- add bidirectional sync workflow ([7a55864](https://github.com/ExaDev/claude-code-action/commit/7a5586445e0f8333c8efc13506918806f0382699))
- add release automation and Turborepo task caching ([ba42065](https://github.com/ExaDev/claude-code-action/commit/ba42065892e664b7ba00e0bb0f708c0cb0fb3d49))
- add reusable workflows, Dependabot investigate-and-adapt pipeline, and updated examples ([a73864c](https://github.com/ExaDev/claude-code-action/commit/a73864c1e0748326368ef0a70629806435de04f3))
- add scheduled upstream sync workflow ([529c2e2](https://github.com/ExaDev/claude-code-action/commit/529c2e209e48e0eca969935ea5394c109ebc8f10))
- bring action.yml to full feature parity with the sophisticated lineage ([26d2e03](https://github.com/ExaDev/claude-code-action/commit/26d2e038b40933066293efeb0ceea8cb30aa5ad4))
- fall through to a backup credential when Claude Code fails to run ([7d2c669](https://github.com/ExaDev/claude-code-action/commit/7d2c66904f3215de9fc72de84c375d3b0193ac01))
- list all feedback to avoid duplicating others' comments ([982bc87](https://github.com/ExaDev/claude-code-action/commit/982bc87b155ac3b45eba9ee17a7744e20e95d1f8))
- pass a second credential to this repository's own dogfooding runs ([2ece7a6](https://github.com/ExaDev/claude-code-action/commit/2ece7a63083dc71d731bb2b6382ed3f8766364bd))
- **prompts:** add conduct guidelines for interactive mode ([8c361ee](https://github.com/ExaDev/claude-code-action/commit/8c361ee9273f75063960616e8d008e010b52c475))
- **prompts:** add interactive mode placeholder ([964817e](https://github.com/ExaDev/claude-code-action/commit/964817e5f8fec819c4cec11a77ef20aa21270039))
- **prompts:** add issue-linking guidance to PR description updates ([e93b1b6](https://github.com/ExaDev/claude-code-action/commit/e93b1b68505f204a094a78361ad554e8c40715cd))
- **prompts:** add red flags checklist for code review ([a1741bd](https://github.com/ExaDev/claude-code-action/commit/a1741bd02fc8295e7040b5e5fe3f95892035e2d0))
- **prompts:** add review mode instructions ([47b39c8](https://github.com/ExaDev/claude-code-action/commit/47b39c8a9f8aee5da66dce3845508172351c156a))
- **prompts:** add self-improvement prompt for review mode ([c59bf88](https://github.com/ExaDev/claude-code-action/commit/c59bf887bdd5a0ca3c87939db9f05298e4e30b0c))
- **prompts:** add shared prompts for all modes ([d36aee8](https://github.com/ExaDev/claude-code-action/commit/d36aee801997e0a1a7e2d162f59f82a8d94959c7))
- **prompts:** enhance review command with security checks ([52a768e](https://github.com/ExaDev/claude-code-action/commit/52a768eb87f1b7b694982778081b58e53803e8bc))
- **sync:** enable auto-merge on sync PRs ([9158a73](https://github.com/ExaDev/claude-code-action/commit/9158a73a04c91fd261870932843297270d8f3772))
- **sync:** include CLI changelog in upstream sync context ([8d2670c](https://github.com/ExaDev/claude-code-action/commit/8d2670ceee9c77d734028f69107f574b9c4d3651))
- **sync:** use rebase merge method for linear history ([fe2cff9](https://github.com/ExaDev/claude-code-action/commit/fe2cff930e1e47b4f6af5c32c1ad17ed84a99112))
- **triage:** add API discovery prompt ([c0c0b25](https://github.com/ExaDev/claude-code-action/commit/c0c0b2557156517796ef296d88ff6c00820c43c3))
- **triage:** add core triage task prompt ([1b3bdf6](https://github.com/ExaDev/claude-code-action/commit/1b3bdf661304223fb35d79f2245af8d847d8d844))
- **triage:** add triage mode to action.yml ([e3a5605](https://github.com/ExaDev/claude-code-action/commit/e3a56050eed04119e14a51ac871b896f462c611e))
- **triage:** add triage quality guidelines prompt ([6663efc](https://github.com/ExaDev/claude-code-action/commit/6663efcdc955e1da47e95116ff7323f0368efaa2))
- **triage:** add triage workflow template ([804f02c](https://github.com/ExaDev/claude-code-action/commit/804f02c95b42623476e08067c2da8d5ed49f62e8))
- **upstream-sync:** extract sync prompt into dedicated prompt file ([3215e45](https://github.com/ExaDev/claude-code-action/commit/3215e452eea1da8adf0c0d30ef1c417ea8f25011))
- **workflow:** add issue/PR creation tools to review mode ([b23f0f3](https://github.com/ExaDev/claude-code-action/commit/b23f0f3961b778801019b0e0b28d55c78b7c043f))
- **workflows:** add interactive and review trigger workflows ([84621e0](https://github.com/ExaDev/claude-code-action/commit/84621e07c1532213528b023e7595d70af788dc21))
- **workflows:** add reusable claude-base workflow ([329a0c4](https://github.com/ExaDev/claude-code-action/commit/329a0c48e5dc998a599682eca0936f622bf19581))
- **workflow:** use GitHub App token for cross-repo access ([96e2786](https://github.com/ExaDev/claude-code-action/commit/96e27861c23910d67e93d4b0f3df2490d48930f2))

### Reverts

- remove workflows permission from workflow file ([4c8b241](https://github.com/ExaDev/claude-code-action/commit/4c8b241e86bda8f85a40cbdf57daaacb8a006bfd))

### BREAKING CHANGES

- for its real production consumers, who still expect
  the simple, upstream-delegating design. adpeak moving onto this
  repository directly is a separate, later migration step.

upstream-sync.yml (a weekly cron that used Claude Code to check for
and adapt to anthropics/claude-code-action releases) is superseded by
the ported Dependabot investigate-and-adapt pipeline, which does the
same job triggered by an actual upstream release rather than a fixed
schedule. It was already broken by the prompts/ directory
restructuring, since it depended on the now-removed
.github/prompts/upstream-sync/01-sync-task.md.

debug-app.yml, minimal-push.yml, test-git-push.yml, test-main-push.yml,
and TEST_SYNC.md were scratch workflows and a test file built while
originally developing bidirectional-sync.yml; dead once it's gone.

docs/plans/2026-02-23-issue-triage-*.md describe the now-superseded
envsubst-based triage architecture in specific technical detail --
kept as-is they would actively mislead a future reader about how
triage mode actually works, not just be dated.
