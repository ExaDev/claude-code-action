// lint-staged loads a TypeScript config via dynamic import of the raw file, relying on Node's native type-stripping, which is only on by default from Node 23.6 onward -- this repository's documented supported version (see the root "engines" field in package.json) was raised to match, so this can now be a real .ts file like the repository's other *.config.ts files instead of needing a plain-JS carve-out.

// eslint.config.ts excludes package-lock.json from lint entirely (generated, not hand-maintained); the `!(package-lock).json` glob below applies the same exclusion to prettier, which has no ignores option of its own here.
import { defineConfig } from "lint-staged/config";

export default defineConfig({
  "*.{ts,md}": [
    "eslint --fix --cache --cache-location node_modules/.cache/eslint/.eslintcache",
    "prettier --write --cache",
  ],
  "*.json":
    "eslint --fix --cache --cache-location node_modules/.cache/eslint/.eslintcache",
  "!(package-lock).json": "prettier --write --cache",
  "*.{yml,yaml}": "prettier --write --cache",
});
