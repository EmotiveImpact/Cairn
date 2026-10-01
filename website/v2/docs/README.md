# Cairn documentation source

This folder is a Mintlify documentation project. `docs.json` defines the theme and navigation; the `.mdx` files are the source pages. The Cairn website links to an offline preview generated from these same pages at `../docs-preview/index.html`.

From the website concept folder, run `npm run build:docs` after editing any page. This regenerates the local HTML preview without a service or account.

For a native Mintlify preview, install the current `mint` CLI and run `mint dev` from this folder. Mintlify's current quickstart describes `npm i -g mint` and `mint dev`. No Mintlify account, Git connection, custom domain, or publication is configured in this workspace.

Content describes a product in development. Recheck native implementation and release status before publishing or adding installation instructions.
