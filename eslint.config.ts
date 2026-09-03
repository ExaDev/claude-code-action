import { defineConfig } from "eslint/config";
import tseslint from "typescript-eslint";
import json from "@eslint/json";
import markdown from "@eslint/markdown";
// Recommended config, not the plugin itself: this both enables the prettier/prettier rule (reports formatting differences as lint errors, reading prettier.config.ts the same way `prettier --check` does) and applies eslint-config-prettier, which turns off every ESLint stylistic rule that could otherwise disagree with Prettier. It carries no `files:` restriction of its own, so it applies to everything ESLint actually lints below — YAML is untouched here (no ESLint language plugin for it), so `npm run format:check` remains the one authoritative formatting check that also covers the workflow/action YAML files.
import eslintPluginPrettierRecommended from "eslint-plugin-prettier/recommended";

export default defineConfig([
  {
    files: ["**/*.ts"],
    extends: [tseslint.configs.recommended],
  },
  {
    files: ["**/*.json"],
    ignores: ["package-lock.json"], // generated, not hand-maintained
    language: "json/json",
    plugins: { json },
    extends: ["json/recommended"],
  },
  {
    // gfm, not commonmark: every markdown file here is rendered on GitHub, and relies on GFM-only syntax CommonMark doesn't define at all — tables throughout this README, task-list-style content elsewhere.
    files: ["**/*.md"],
    ignores: ["CHANGELOG.md"], // generated, not hand-maintained — a commit subject containing `claude[bot]` reads its own `[bot]` as an unresolved markdown reference-link label to this rule, which has no way to know it's plain text quoting a GitHub bot account name
    plugins: { markdown },
    language: "markdown/gfm",
    extends: ["markdown/recommended"],
  },
  eslintPluginPrettierRecommended,
]);
