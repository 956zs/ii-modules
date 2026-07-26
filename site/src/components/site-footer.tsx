import { BookOpen, FileText, GitPullRequest, ScrollText } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { GitHubIcon } from '@/components/site-header'
import { ADD_MODULE_URL, DOCS_URL, REGISTRY_URL, REPO_URL, SPEC_URL } from '@/lib/urls'

export function SiteFooter() {
  return (
    <footer className="border-t border-border/60">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 px-4 py-10 sm:px-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-col gap-1">
            <span className="font-mono text-sm font-semibold tracking-wide">
              IIMP<span className="text-brand">.</span>
            </span>
            <p className="text-xs text-muted-foreground">
              聯邦式模塊清單——每個模塊自帶更新來源，清單只負責索引。
            </p>
          </div>
          <Button asChild variant="outline" size="sm">
            <a href={ADD_MODULE_URL} target="_blank" rel="noreferrer">
              <GitPullRequest data-icon="inline-start" />
              新增模塊
            </a>
          </Button>
        </div>

        <Separator />

        <div className="flex flex-wrap items-center justify-between gap-4 text-xs text-muted-foreground">
          <nav aria-label="網站連結" className="flex flex-wrap items-center gap-4">
            <a
              href={DOCS_URL}
              className="flex items-center gap-1.5 transition-colors duration-150 hover:text-foreground"
            >
              <BookOpen className="size-3.5" />
              文件
            </a>
            <a
              href={REPO_URL}
              target="_blank"
              rel="noreferrer"
              className="flex items-center gap-1.5 transition-colors duration-150 hover:text-foreground"
            >
              <GitHubIcon className="size-3.5" />
              GitHub Repo
            </a>
            <a
              href={SPEC_URL}
              target="_blank"
              rel="noreferrer"
              className="flex items-center gap-1.5 transition-colors duration-150 hover:text-foreground"
            >
              <FileText className="size-3.5" />
              SPEC-1.0.md
            </a>
            <a
              href={REGISTRY_URL}
              target="_blank"
              rel="noreferrer"
              className="flex items-center gap-1.5 transition-colors duration-150 hover:text-foreground"
            >
              <ScrollText className="size-3.5" />
              registry.json
            </a>
          </nav>
          <span className="font-mono">ii.n1cat.xyz</span>
        </div>
      </div>
    </footer>
  )
}
