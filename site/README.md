# IIMP module listing site

The IIMP (illogical-impulse Module Protocol) module listing site. Built with Vite + React + TypeScript + Tailwind CSS + shadcn/ui.

- `scripts/module-catalog.mjs` — validates every `modules/*/module.json` plus README and derives the landing catalog, module docs routes, and VitePress navigation from that single source.
- `public/registry.json` — generated deploy artifact. Run `npm run catalog:generate` after manifest changes; `npm run catalog:check` and the production build fail when it is stale.
- `src/lib/version.ts` — release resolution is separate from source metadata: it reads `index.json.modules[id]`, falls back to the matching GitHub release asset, and only enables downloads when the released version matches the manifest version.

## Development

```bash
npm install
npm run catalog:generate
npm run dev
```

## Build

```bash
npm run build   # tsc -b && vite build, outputs to dist/
npm run preview
```

Deployed to GitHub Pages by `.github/workflows/pages.yml` on push to `main` under `site/**`.
