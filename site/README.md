# IIMP module listing site

The IIMP (illogical-impulse Module Protocol) module listing site. Built with Vite + React + TypeScript + Tailwind CSS + shadcn/ui.

- `public/registry.json` — curated list of known modules. Each entry only carries static metadata plus an `origin` pointing at that module's own `index.json`; live version, download URL, and sha256 are fetched from `origin` at page load (federated updates, no site redeploy required).
- `src/lib/version.ts` — live version resolution: direct fetch of `origin` first, falling back to the GitHub REST API (release asset lookup) on CORS failure, with a 10-minute `sessionStorage` cache.

## Development

```bash
npm install
npm run dev
```

## Build

```bash
npm run build   # tsc -b && vite build, outputs to dist/
npm run preview
```

Deployed to GitHub Pages by `.github/workflows/pages.yml` on push to `main` under `site/**`.
