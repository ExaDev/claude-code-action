// Plain JS, not lint-staged.config.ts like the repository's other *.config.ts files: lint-staged loads a TypeScript config via dynamic import of the raw file, relying on Node's native type-stripping, which is only on by default from Node 23.6 onward and needs an explicit --experimental-strip-types flag on the Node 22 this repository's CI (and therefore its documented supported version) actually runs. A plain ESM config needs no flag on any supported Node version.

// eslint.config.ts excludes package-lock.json from lint entirely (generated, not hand-maintained); the `!(package-lock).json` glob below applies the same exclusion to prettier, which has no ignores option of its own here.
export default {
  "*.{ts,md}": [
    "eslint --fix --cache --cache-location node_modules/.cache/eslint/.eslintcache",
    "prettier --write --cache",
  ],
  "*.json":
    "eslint --fix --cache --cache-location node_modules/.cache/eslint/.eslintcache",
  "!(package-lock).json": "prettier --write --cache",
  "*.{yml,yaml}": "prettier --write --cache",
};
