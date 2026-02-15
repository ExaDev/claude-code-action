import markdown from "@eslint/markdown"
import stylistic from "@stylistic/eslint-plugin"
import prettier from "eslint-plugin-prettier"
import yml from "eslint-plugin-yml"
import { defineConfig } from "eslint/config"

export default defineConfig([
	{
		files: ["**/*.{js,ts,mjs,mts}"],
		...stylistic.configs.customize({
			indent: "tab",
			quotes: "double",
		}),
	},
	{
		files: ["**/*.md"],
		plugins: { markdown, prettier },
		extends: ["markdown/recommended"],
		language: "markdown/gfm",
		rules: {
			"prettier/prettier": ["error", {
				useTabs: true,
				singleQuote: false,
				proseWrap: "preserve",
			}],
		},
	},
	...yml.configs["flat/recommended"],
	{
		ignores: [".git/", "node_modules/", ".claude/", "CLAUDE.md", "AGENTS.md"],
	},
])
