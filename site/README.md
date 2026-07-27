# IIMP module listing site

The IIMP (illogical-impulse Module Protocol) module listing site. Built with Vite + React + TypeScript + Tailwind CSS + shadcn/ui.

- `scripts/module-catalog.mjs` — validates every `modules/*/module.json` plus README and derives the landing catalog, module docs routes, and VitePress navigation from that single source.
- `public/registry.json` — generated deploy artifact. `npm run build` regenerates it automatically from the current checkout; `npm run catalog:check` remains available for CI/review jobs that want to detect an unrefreshed committed artifact.
- `src/lib/version.ts` — release resolution is separate from source metadata: it reads the canonical Pages `index.json.modules[id]` contract and only enables downloads when the released version matches the manifest version.

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

Deployed to GitHub Pages by `.github/workflows/pages.yml` on pushes to `main` that touch `site/**`, `modules/**`, or the workflow itself. The build regenerates the catalog, landing-page module list, VitePress module routes, and navigation from the checked-out manifests and READMEs before deployment.
