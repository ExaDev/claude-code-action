Review pull request #${PR_NUMBER} in ${REPO}.

Focus on the diff — only flag issues introduced by this PR, not pre-existing
problems. Use `git blame` or file history when you need context on why code
exists.

What to look for:

- Bugs and logic errors
- Security vulnerabilities
- Breaking changes or regressions
- Violations of conventions in CLAUDE.md

What to ignore:

- Style nitpicks that a linter would catch
- Pre-existing issues untouched by this PR
- Matters of personal preference

Only flag issues you are confident about. A false positive wastes more of the
author's time than a missed minor issue. If you are unsure, leave it out.
