import { ArrowRight, BookOpen } from 'lucide-react'
import { CommandBlock } from '@/components/command-block'
import { Skeleton } from '@/components/ui/skeleton'
import { DOCS_URL } from '@/lib/urls'
import type { RegistryModule, VersionState } from '@/lib/types'

const INSTALL_IIMOD_COMMAND =
  'curl -fsSL -o iimod https://github.com/956zs/ii-modules/releases/latest/download/iimod-linux-x86_64 && chmod +x iimod && sudo install iimod /usr/local/bin/iimod'

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
  const packageUrl =
    firstModuleVersion?.status === 'success' ? firstModuleVersion.data.url : firstModule?.origin
  const stepTwoLoading =
    !registryFailed && (!firstModule || firstModuleVersion?.status === 'loading')

  return (
    <section className="mx-auto flex max-w-[96rem] flex-col items-center gap-6 px-4 pt-12 pb-12 text-center sm:px-6 sm:pt-20 sm:pb-16">
      <span className="rounded-full border border-border bg-card/60 px-3 py-1 font-mono text-xs tracking-wide text-muted-foreground uppercase">
        IIMP · illogical-impulse Module Protocol
      </span>
      <h1 className="font-heading text-3xl font-semibold tracking-tight text-balance sm:text-5xl">
        給 illogical-impulse 桌面的
        <br />
        <span className="text-brand">社群模塊協議</span>
      </h1>
      <p className="max-w-2xl text-base text-muted-foreground sm:text-lg">
        IIMP 讓 Quickshell 模塊像套件一樣安裝、更新與分享——每個模塊自帶更新來源，
        清單只負責索引，版本永遠即時。
      </p>

      {/* Hugs the widest command on desktop so width follows the viewport
          instead of a fixed column; full-width on mobile. */}
      <div className="mt-4 w-full max-w-full rounded-xl border border-border bg-card/40 p-4 text-left backdrop-blur-sm sm:w-fit sm:p-5">
        <h2 className="mb-4 font-mono text-xs tracking-wide text-muted-foreground uppercase">
          快速安裝
        </h2>
        <ol className="flex flex-col gap-4">
          <InstallStep step={1} title="安裝 iimod CLI（來自 GitHub Releases）">
            <CommandBlock command={INSTALL_IIMOD_COMMAND} />
          </InstallStep>
          <InstallStep
            step={2}
            title={firstModule ? `安裝模塊——例如「${firstModule.name.zh_TW}」` : '安裝模塊'}
          >
            {stepTwoLoading ? (
              <Skeleton className="h-[38px] w-full rounded-lg" />
            ) : packageUrl ? (
              <CommandBlock command={`iimod install ${packageUrl}`} />
            ) : (
              <p className="text-sm text-muted-foreground">
                {registryFailed
                  ? '模塊清單暫時無法取得，請稍後再試。'
                  : '從下方清單挑選模塊，複製對應的安裝指令。'}
              </p>
            )}
          </InstallStep>
        </ol>
      </div>

      <a
        href={DOCS_URL}
        className="group flex items-center gap-1.5 rounded-md text-sm text-muted-foreground outline-none transition-colors duration-150 hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring/60"
      >
        <BookOpen className="size-4" />
        閱讀完整教學與文件
        <ArrowRight className="size-3.5 transition-transform duration-150 group-hover:translate-x-0.5 motion-reduce:transition-none" />
      </a>
    </section>
  )
}
