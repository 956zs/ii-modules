import { ArrowRight, BookOpen } from 'lucide-react'
import { CommandBlock } from '@/components/command-block'
import { Skeleton } from '@/components/ui/skeleton'
import { docsUrl, useI18n } from '@/lib/i18n'
import { INSTALL_IIMOD_COMMAND, installCommand } from '@/lib/install'
import type { RegistryModule, VersionState } from '@/lib/types'

interface HeroProps {
  firstModule?: RegistryModule
  firstModuleVersion?: VersionState
  /** True once the registry fetch has failed — stops the step-2 skeleton. */
  registryFailed?: boolean
}

interface InstallStepProps {
  step: number
  title: string
  children: React.ReactNode
}

function InstallStep({ step, title, children }: InstallStepProps) {
  return (
    <li className="flex gap-3">
      <span className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full border border-brand/40 bg-brand/10 font-mono text-xs text-brand">
        {step}
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
        <span className="text-sm font-medium text-foreground/90">{title}</span>
        {children}
      </div>
    </li>
  )
}

export function Hero({ firstModule, firstModuleVersion, registryFailed }: HeroProps) {
  const { t, locale } = useI18n()
  const packageUrl =
    firstModuleVersion?.status === 'success' ? firstModuleVersion.data.url : undefined
  const stepTwoLoading =
    !registryFailed && (!firstModule || firstModuleVersion?.status === 'loading')

  return (
    <section className="mx-auto flex max-w-[96rem] flex-col items-center gap-6 px-4 pt-12 pb-12 text-center sm:px-6 sm:pt-20 sm:pb-16">
      <span className="rounded-full border border-border bg-card/60 px-3 py-1 font-mono text-xs tracking-wide text-muted-foreground uppercase">
        IIMP · illogical-impulse Module Protocol
      </span>
      <h1 className="font-heading text-3xl font-semibold tracking-tight text-balance sm:text-5xl">
        {t.heroTitleTop}
        <br />
        <span className="text-brand">{t.heroTitleBrand}</span>
      </h1>
      <p className="max-w-2xl text-base text-muted-foreground sm:text-lg">{t.heroTagline}</p>

      {/* Hugs the widest command on desktop so width follows the viewport
          instead of a fixed column; full-width on mobile. */}
      <div className="mt-4 w-full max-w-full rounded-xl border border-border bg-card/40 p-4 text-left backdrop-blur-sm sm:w-fit sm:p-5">
        <h2 className="mb-4 font-mono text-xs tracking-wide text-muted-foreground uppercase">
          {t.quickInstall}
        </h2>
        <ol className="flex flex-col gap-4">
          <InstallStep step={1} title={t.stepInstallCli}>
            <CommandBlock command={INSTALL_IIMOD_COMMAND} />
          </InstallStep>
          <InstallStep
            step={2}
            title={
              firstModule
                ? t.stepInstallModuleExample(firstModule.name[locale])
                : t.stepInstallModule
            }
          >
            {stepTwoLoading ? (
              <Skeleton className="h-[38px] w-full rounded-lg" />
            ) : packageUrl ? (
              <CommandBlock command={installCommand(packageUrl, firstModule?.tierB ?? false)} />
            ) : (
              <p className="text-sm text-muted-foreground">
                {registryFailed ? t.registryFailedHero : t.pickFromList}
              </p>
            )}
          </InstallStep>
        </ol>
      </div>

      <a
        href={docsUrl(locale)}
        className="group flex items-center gap-1.5 rounded-md text-sm text-muted-foreground outline-none transition-colors duration-150 hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring/60"
      >
        <BookOpen className="size-4" />
        {t.readDocs}
        <ArrowRight className="size-3.5 transition-transform duration-150 group-hover:translate-x-0.5 motion-reduce:transition-none" />
      </a>
    </section>
  )
}
