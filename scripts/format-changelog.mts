import { readFile, writeFile } from "node:fs/promises";
import * as prettier from "prettier";
import { join } from "node:path";

/**
 * semantic-release plugin, referenced by path from release.config.ts. Runs Prettier over CHANGELOG.md after @semantic-release/changelog has generated it and before @semantic-release/git commits it, so the committed changelog always satisfies this repository's format:check job.
 *
 * Without this, conventional-changelog-writer's output (asterisk bullets, double blank lines between commit groups) fails `prettier --check CHANGELOG.md`, and since the release commit is `[skip ci]` the failure surfaces only on the *next* push to main — by which point a broken CHANGELOG is already on the branch and blocking the subsequent release. Formatting at generation time is the root-cause fix; excluding CHANGELOG.md from Prettier would only hide the mismatch.
 *
 * Runs in the `prepare` step, so it must be listed after @semantic-release/changelog (which writes the file) and before @semantic-release/git (which commits it) in release.config.ts's plugin order.
 *
 * Uses Prettier's programmatic API with the `filepath` option so it resolves and applies prettier.config.ts exactly as the CLI `prettier --write` would, including the double-quote setting.
 */
export async function prepare(_pluginConfig, context) {
  const { cwd, logger } = context;
  const filePath = join(cwd, "CHANGELOG.md");
  const text = await readFile(filePath, "utf8");
  const formatted = await prettier.format(text, { filepath: "CHANGELOG.md" });
  await writeFile(filePath, formatted);
  logger.log("Formatted CHANGELOG.md with Prettier");
}
