import { BookOpen, FileText, GitPullRequest, ScrollText } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { GitHubIcon } from '@/components/site-header'
import { docsUrl, useI18n } from '@/lib/i18n'
import { ADD_MODULE_URL, REGISTRY_URL, REPO_URL, SPEC_URL } from '@/lib/urls'

export function SiteFooter() {
  const { t, locale } = useI18n()
  return (
    <footer className="border-t border-border/60">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 px-4 py-10 sm:px-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-col gap-1">
            <span className="font-mono text-sm font-semibold tracking-wide">
              IIMP<span className="text-brand">.</span>
            </span>
            <p className="text-xs text-muted-foreground">{t.footerTagline}</p>
          </div>
          <Button asChild variant="outline" size="sm">
            <a href={ADD_MODULE_URL} target="_blank" rel="noreferrer">
              <GitPullRequest data-icon="inline-start" />
              {t.addModule}
            </a>
          </Button>
        </div>

        <Separator />

        <div className="flex flex-wrap items-center justify-between gap-4 text-xs text-muted-foreground">
          <nav aria-label={t.siteLinks} className="flex flex-wrap items-center gap-4">
            <a
              href={docsUrl(locale)}
              className="flex items-center gap-1.5 transition-colors duration-150 hover:text-foreground"
            >
              <BookOpen className="size-3.5" />
              {t.docs}
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
