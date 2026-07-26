import { FileText, GitFork, GitPullRequest } from 'lucide-react'

const REPO_URL = 'https://github.com/956zs/ii-modules'
const SPEC_URL = `${REPO_URL}/blob/main/spec/SPEC-1.0.md`
const REGISTRY_URL = `${REPO_URL}/blob/main/site/public/registry.json`

export function SiteFooter() {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto flex max-w-6xl flex-col gap-4 px-6 py-10 text-sm text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-wrap items-center gap-4">
          <a
            href={REPO_URL}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-1.5 hover:text-foreground"
          >
            <GitFork className="size-4" />
            GitHub Repo
          </a>
          <a
            href={SPEC_URL}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-1.5 hover:text-foreground"
          >
            <FileText className="size-4" />
            SPEC-1.0.md
          </a>
          <a
            href={REGISTRY_URL}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-1.5 hover:text-foreground"
          >
            <GitPullRequest className="size-4" />
            新增模塊（PR registry.json）
          </a>
        </div>
        <p className="text-xs">
          聯邦式模塊清單：每個模塊自帶更新來源，新增模塊只需送出一個 PR 到{' '}
          <code className="font-mono">site/public/registry.json</code>。
        </p>
      </div>
    </footer>
  )
}
